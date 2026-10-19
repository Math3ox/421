//! 421 en 3D isométrique : contre un bot, à deux sur le même PC ou en duel en ligne.
//! Fenêtre portable (macroquad : Windows, Linux, macOS) ; `421 -t` joue dans le terminal.

#![windows_subsystem = "windows"]

mod ai;
mod cfg;
mod game;
mod net;
mod render;
mod term;

use game::{Game, Mode};
use macroquad::prelude::*;
use net::{Menu, Net};
use render::{Fonts, Hit, View, WH, WW};

#[cfg(windows)]
mod win {
    use std::ffi::c_void;
    #[repr(C)]
    #[derive(Default)]
    pub struct Rect {
        pub l: i32,
        pub t: i32,
        pub r: i32,
        pub b: i32,
    }
    #[link(name = "user32")]
    extern "system" {
        pub fn SetProcessDPIAware() -> i32;
        pub fn SystemParametersInfoW(action: u32, p1: u32, p2: *mut c_void, p3: u32) -> i32;
    }
    #[link(name = "kernel32")]
    extern "system" {
        pub fn AttachConsole(pid: u32) -> i32;
        pub fn AllocConsole() -> i32;
        pub fn SetConsoleOutputCP(cp: u32) -> i32;
    }

    /// Zone de travail de l'écran (sans la barre des tâches), en pixels réels.
    pub fn work_area() -> (i32, i32) {
        let mut r = Rect::default();
        unsafe {
            SetProcessDPIAware();
            if SystemParametersInfoW(0x30, 0, &mut r as *mut Rect as *mut c_void, 0) == 0 {
                return (1920, 1040);
            }
        }
        (r.r - r.l, r.b - r.t)
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

fn window_conf() -> Conf {
    // 1100 x 800 si l'écran le permet, sinon réduite pour tenir dans la zone de travail
    #[cfg(windows)]
    let (aw, ah) = win::work_area();
    #[cfg(not(windows))]
    let (aw, ah) = (1100 + 16, 800 + 40);
    let k = 1f32.min((aw - 16) as f32 / WW).min((ah - 40) as f32 / WH);
    Conf {
        window_title: "421 - jeu du bistro en 3D isométrique".into(),
        window_width: (WW * k) as i32,
        window_height: (WH * k) as i32,
        window_resizable: true,
        sample_count: 4,
        ..Default::default()
    }
}

fn main() {
    if std::env::args().any(|a| a == "-t") {
        #[cfg(windows)]
        win::console();
        let mut g = Game::new(seed());
        let c = cfg::load(&mut g);
        g.new_game();
        term::run(g, |g| cfg::save(g, &c, false));
        return;
    }
    macroquad::Window::from_config(window_conf(), run());
}

async fn run() {
    let fonts = Fonts::load();
    let mut g = Game::new(seed());
    let mut c = cfg::load(&mut g);
    g.new_game();
    let mut net = Net::new(c.ip.clone());
    let mut fullscreen = c.fullscreen;
    if fullscreen {
        set_fullscreen(true);
    }
    let mut prev_duo = g.mode == Mode::Duo;
    loop {
        let v = View::fit();
        if !g.online() {
            prev_duo = g.mode == Mode::Duo;
        }
        let mut save = false;

        // ---------- clavier ----------
        let mut chars: Vec<char> = Vec::new();
        while let Some(ch) = get_char_pressed() {
            chars.push(ch);
        }
        if net.menu == Menu::Ip {
            if is_key_pressed(KeyCode::Escape) {
                chars = vec!['\u{1b}'];
            } else if is_key_pressed(KeyCode::Enter) || is_key_pressed(KeyCode::KpEnter) {
                chars = vec!['\r'];
            } else if is_key_pressed(KeyCode::Backspace) {
                chars = vec!['\u{8}'];
            }
            for ch in chars {
                if net.ip_char(&mut g, ch) {
                    c.ip = net.ip.clone();
                    save = true;
                }
            }
        } else if net.menu == Menu::Choice {
            if let Some(&ch) = chars.first() {
                net.menu_key(&mut g, ch);
            } else if is_key_pressed(KeyCode::Escape) {
                net.menu_key(&mut g, '\u{1b}');
            }
        } else {
            if is_key_pressed(KeyCode::Escape) {
                if net.pending() {
                    net.close(&mut g, "Multijoueur annulé.");
                } else if fullscreen {
                    fullscreen = false;
                    set_fullscreen(false);
                    c.fullscreen = false;
                    save = true;
                } else {
                    break;
                }
            }
            if is_key_pressed(KeyCode::F11) {
                fullscreen = !fullscreen;
                set_fullscreen(fullscreen);
                c.fullscreen = fullscreen;
                save = true;
            }
            if is_key_pressed(KeyCode::Space) {
                g.ui_main();
            }
            if is_key_pressed(KeyCode::Enter) || is_key_pressed(KeyCode::KpEnter) {
                g.ui_second();
            }
            for ch in chars {
                match ch.to_ascii_uppercase() {
                    'N' => net.open(&mut g),
                    'J' => g.toggle_duo(),
                    'L' => g.cycle_level(),
                    'H' => g.help(),
                    'P' => g.cycle_pot(),
                    _ => {}
                }
            }
        }

        // ---------- souris ----------
        if is_mouse_button_pressed(MouseButton::Left) && net.menu == Menu::None && g.accepts_input() {
            let (x, y) = v.to_game(mouse_position().into());
            match render::hit(&g, x, y) {
                Hit::Main => g.ui_main(),
                Hit::Second => g.ui_second(),
                Hit::Die(i) => g.ui_toggle(i),
                Hit::Nothing => {}
            }
        }

        // ---------- temps, réseau, image ----------
        g.tick((get_frame_time() as f64 * 1000.0).min(100.0));
        net.poll(&mut g);
        if save || g.save_needed {
            g.save_needed = false;
            cfg::save(&g, &c, prev_duo);
        }
        render::draw(&g, v, &fonts);
        if is_key_pressed(KeyCode::F12) {
            // capture : image opaque (les ombres translucides laissent un alpha < 1 dans le tampon)
            let mut img = get_screen_data();
            img.bytes.chunks_mut(4).for_each(|p| p[3] = 255);
            img.export_png("421_shot.png");
        }
        next_frame().await;
    }
}
