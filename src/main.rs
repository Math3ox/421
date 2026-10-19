//! 421 en 3D isométrique : contre un bot, à deux sur le même PC ou en duel en ligne.
//! Dessin 100 % processeur (aucune carte graphique), Windows / Linux / macOS ;
//! `421 -t` joue dans le terminal.

#![windows_subsystem = "windows"]

mod ai;
mod cfg;
mod game;
mod gfx;
mod net;
mod render;
mod shell;
mod term;

use game::{Game, Mode};
use gfx::Gfx;
use net::{Menu, Net};
use render::{Fonts, Hit};
use shell::Key;
use std::hash::{Hash, Hasher};

#[cfg(windows)]
mod win {
    #[link(name = "kernel32")]
    extern "system" {
        pub fn AttachConsole(pid: u32) -> i32;
        pub fn AllocConsole() -> i32;
        pub fn SetConsoleOutputCP(cp: u32) -> i32;
    }

    /// Console pour le mode terminal (celle qui a lancé le jeu, sinon une nouvelle).
    pub fn console() {
        unsafe {
            if AttachConsole(u32::MAX) == 0 {
                AllocConsole();
            }
            SetConsoleOutputCP(65001);
        }
    }
}

fn seed() -> u64 {
    let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
    (t.as_nanos() as u64) ^ 0x2545F4914F6CDD1D ^ (std::process::id() as u64) << 32
}

fn main() {
    let mut g = Game::new(seed());
    let c = cfg::load(&mut g);
    g.new_game();
    if std::env::args().any(|a| a == "-t") {
        #[cfg(windows)]
        win::console();
        term::run(g, |g| cfg::save(g, &c, false));
        return;
    }
    let net = Net::new(c.ip.clone());
    let fullscreen = c.fullscreen;
    let prev_duo = g.mode == Mode::Duo;
    shell::run(App { fonts: Fonts::load(), g, c, net, fullscreen, quit: false, prev_duo, sig: 0 });
}

struct App {
    fonts: Fonts,
    g: Game,
    c: cfg::Cfg,
    net: Net,
    fullscreen: bool,
    quit: bool,
    /// mode local à mémoriser pendant une partie en ligne
    prev_duo: bool,
    /// empreinte de ce qui est affiché : on ne redessine que si elle change
    sig: u64,
}

impl App {
    fn save(&mut self) {
        self.g.save_needed = false;
        cfg::save(&self.g, &self.c, self.prev_duo);
    }

    fn signature(&self) -> u64 {
        let g = &self.g;
        let mut h = std::collections::hash_map::DefaultHasher::new();
        (&g.line1, &g.line2, g.phase, g.pot, g.tok, g.round, g.level, g.wins, g.losses, g.cur).hash(&mut h);
        (format!("{:?}", g.mode), g.can_act()).hash(&mut h);
        for d in &g.dice {
            (d.val, d.held, d.p.map(|v| (v * 1000.0) as i64)).hash(&mut h);
        }
        h.finish()
    }
}

impl shell::Game for App {
    fn title(&self) -> String {
        "421 - jeu du bistro en 3D isométrique".into()
    }

    fn shot_name(&self) -> &str {
        "421_shot.png"
    }

    fn background(&mut self, gfx: &Gfx) {
        render::background(gfx, &self.fonts);
    }

    fn draw(&mut self, gfx: &Gfx) {
        render::draw(&self.g, gfx, &self.fonts);
    }

    fn tick(&mut self, dt: f64) -> bool {
        if !self.g.online() {
            self.prev_duo = self.g.mode == Mode::Duo;
        }
        self.g.tick(dt);
        self.net.poll(&mut self.g);
        if self.g.save_needed {
            self.save();
        }
        let sig = self.signature();
        let changed = sig != self.sig;
        self.sig = sig;
        changed
    }

    fn animating(&self) -> bool {
        self.g.rolling
    }

    fn key(&mut self, k: Key) {
        let g = &mut self.g;
        let net = &mut self.net;
        match net.menu {
            Menu::Ip => {
                let ch = match k {
                    Key::Esc => '\u{1b}',
                    Key::Enter => '\r',
                    Key::Back => '\u{8}',
                    Key::Char(c) => c,
                    _ => return,
                };
                if net.ip_char(g, ch) {
                    self.c.ip = net.ip.clone();
                    self.save();
                }
            }
            Menu::Choice => match k {
                Key::Char(c) => net.menu_key(g, c),
                Key::Esc => net.menu_key(g, '\u{1b}'),
                _ => {}
            },
            Menu::None => match k {
                Key::Esc => {
                    if net.pending() {
                        net.close(g, "Multijoueur annulé.");
                    } else if self.fullscreen {
                        self.fullscreen = false;
                        self.c.fullscreen = false;
                        self.save();
                    } else {
                        self.quit = true;
                    }
                }
                Key::F11 => {
                    self.fullscreen = !self.fullscreen;
                    self.c.fullscreen = self.fullscreen;
                    self.save();
                }
                Key::Space => g.ui_main(),
                Key::Enter => g.ui_second(),
                Key::Char(c) => match c.to_ascii_uppercase() {
                    'N' => net.open(g),
                    'J' => g.toggle_duo(),
                    'L' => g.cycle_level(),
                    'H' => g.help(),
                    'P' => g.cycle_pot(),
                    _ => {}
                },
                _ => {}
            },
        }
        if self.g.save_needed {
            self.save();
        }
    }

    fn click(&mut self, x: f32, y: f32) {
        if self.net.menu != Menu::None || !self.g.accepts_input() {
            return;
        }
        match render::hit(&self.g, x as f64, y as f64) {
            Hit::Main => self.g.ui_main(),
            Hit::Second => self.g.ui_second(),
            Hit::Die(i) => self.g.ui_toggle(i),
            Hit::Nothing => {}
        }
    }

    fn hover(&mut self, _x: f32, _y: f32) -> bool {
        false
    }

    fn fullscreen(&self) -> bool {
        self.fullscreen
    }

    fn quit(&self) -> bool {
        self.quit
    }
}
