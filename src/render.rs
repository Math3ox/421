//! Dessin de la table en projection isométrique : tapis, jetons, boutons 3D, dés (faces éclairées,
//! points, ombres portées), textes. Le jeu est dessiné dans un espace virtuel de 1100 x 800,
//! mis à l'échelle de la fenêtre (proportions gardées, bandes noires si besoin).

use crate::ai;
use crate::game::{mv3, Die, Game, Phase, DIE_H, FACES, FELT};
use macroquad::prelude::*;

pub const WW: f32 = 1100.0;
pub const WH: f32 = 800.0;
const S: f64 = 64.0; // échelle monde -> pixels
const CX: f64 = 550.0;
const CY: f64 = 450.0;
const R0: f64 = std::f64::consts::FRAC_1_SQRT_2;
const U0: f64 = 0.40824829046386302;
const U2: f64 = 0.81649658092772604;
const YSQ: f64 = 0.57735026918962576;

const BTN_A: f64 = 4.9;
const BTN_B: [f64; 2] = [-1.0, 1.0];
const BTN_TZ: f64 = 0.41;
const BOT_Z: f64 = -4.3;
const PL_Z: f64 = 4.8;
const POT_A: f64 = -4.6;

const fn rgb(r: u8, g: u8, b: u8) -> Color {
    Color::new(r as f32 / 255.0, g as f32 / 255.0, b as f32 / 255.0, 1.0)
}
const C_BG: Color = rgb(18, 22, 29);
const C_FLOORSH: Color = rgb(10, 13, 18);
const C_WOOD: Color = rgb(128, 84, 44);
const C_WOODSIDE: Color = rgb(78, 48, 24);
const C_WOODLINE: Color = rgb(52, 32, 16);
const C_EDGE: Color = rgb(150, 142, 120);
const C_PIP: Color = rgb(26, 26, 32);
const C_PIPRED: Color = rgb(196, 30, 30);
const C_ZONE: Color = rgb(40, 160, 104);
const C_GOLD: Color = rgb(255, 205, 70);
const C_POTTOP: Color = rgb(255, 214, 70);
const C_POTSIDE: Color = rgb(176, 132, 20);
const C_PLTOP: Color = rgb(96, 200, 255);
const C_PLSIDE: Color = rgb(30, 104, 160);
const C_BOTTOP: Color = rgb(255, 110, 130);
const C_BOTSIDE: Color = rgb(150, 40, 62);
const C_WHITE: Color = rgb(240, 240, 235);
const C_TXTGND: Color = rgb(190, 235, 205);
const C_HELDDISC: Color = rgb(176, 140, 36);
const C_HINT: Color = rgb(128, 138, 150);
const C_BTNG: (Color, Color) = (rgb(255, 196, 64), rgb(176, 118, 20));
const C_BTNB: (Color, Color) = (rgb(96, 200, 255), rgb(30, 104, 160));
const C_BTNX: (Color, Color) = (rgb(92, 106, 100), rgb(58, 68, 64));
const C_BTNTXT: Color = rgb(28, 24, 16);
const C_BTNTXTX: Color = rgb(150, 162, 156);

const PIPMASK: [u16; 6] = [0x010, 0x101, 0x111, 0x145, 0x155, 0x16D];
const PIPX: [f64; 9] = [-0.5, 0.0, 0.5, -0.5, 0.0, 0.5, -0.5, 0.0, 0.5];
const PIPY: [f64; 9] = [-0.5, -0.5, -0.5, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5];

pub const HINT: &str = "J : 1/2 joueurs  -  L : bot  -  H : aide  -  P : pot  -  N : en ligne  -  F11 : plein écran";

/// Mise à l'échelle de l'espace virtuel 1100 x 800 vers la fenêtre.
#[derive(Clone, Copy)]
pub struct View {
    pub sc: f32,
    pub ox: f32,
    pub oy: f32,
}

impl View {
    pub fn fit() -> View {
        let (w, h) = (screen_width(), screen_height());
        let sc = (w / WW).min(h / WH);
        View { sc, ox: ((w - WW * sc) / 2.0).floor(), oy: ((h - WH * sc) / 2.0).floor() }
    }
    fn pt(&self, x: f64, y: f64) -> Vec2 {
        vec2(self.ox + x as f32 * self.sc, self.oy + y as f32 * self.sc)
    }
    /// Pixels de la fenêtre -> coordonnées du jeu.
    pub fn to_game(&self, p: Vec2) -> (f64, f64) {
        (((p.x - self.ox) / self.sc) as f64, ((p.y - self.oy) / self.sc) as f64)
    }
}

pub struct Fonts {
    bold: Option<Font>,
    semi: Option<Font>,
}

fn load_font(paths: &[&str]) -> Option<Font> {
    paths.iter().find_map(|p| std::fs::read(p).ok().and_then(|b| load_ttf_font_from_bytes(&b).ok()))
}

impl Fonts {
    pub fn load() -> Fonts {
        let bold = load_font(&[
            "C:\\Windows\\Fonts\\segoeuib.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans-Bold.ttf",
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        ]);
        let semi = load_font(&[
            "C:\\Windows\\Fonts\\seguisb.ttf",
            "C:\\Windows\\Fonts\\segoeui.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/TTF/DejaVuSans.ttf",
            "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
        ])
        .or_else(|| bold.clone());
        Fonts { bold, semi }
    }
}

// ---------- projections ----------

/// Point monde (x, y, z) -> écran (coordonnées du jeu).
fn proj(p: [f64; 3]) -> (f64, f64) {
    ((p[0] - p[1]) * R0 * S + CX, CY - ((p[0] + p[1]) * U0 + p[2] * U2) * S)
}

/// Point du plateau (a vers la droite, b vers le joueur, hauteur z) -> écran.
fn ground(a: f64, b: f64, z: f64) -> (f64, f64) {
    (a * S + CX, b * S * YSQ + CY - z * S * U2)
}

// ---------- primitives ----------

struct Pen<'a> {
    v: View,
    fonts: &'a Fonts,
}

impl Pen<'_> {
    fn fill(&self, pts: &[(f64, f64)], c: Color) {
        let p: Vec<Vec2> = pts.iter().map(|&(x, y)| self.v.pt(x, y)).collect();
        for i in 1..p.len().saturating_sub(1) {
            draw_triangle(p[0], p[i], p[i + 1], c);
        }
    }

    fn outline(&self, pts: &[(f64, f64)], c: Color, w: f32) {
        for i in 0..pts.len() {
            let a = self.v.pt(pts[i].0, pts[i].1);
            let b = self.v.pt(pts[(i + 1) % pts.len()].0, pts[(i + 1) % pts.len()].1);
            draw_line(a.x, a.y, b.x, b.y, w * self.v.sc, c);
        }
    }

    fn ellipse_pts(cx: f64, cy: f64, rx: f64, ry: f64) -> Vec<(f64, f64)> {
        const N: usize = 64;
        (0..N)
            .map(|i| {
                let t = i as f64 * std::f64::consts::TAU / N as f64;
                (cx + rx * t.cos(), cy + ry * t.sin())
            })
            .collect()
    }

    /// Disque posé sur le plateau (a, b, z), rayon en unités monde.
    fn ground_ellipse(&self, a: f64, b: f64, z: f64, r: f64) -> Vec<(f64, f64)> {
        let (x, y) = ground(a, b, z);
        Self::ellipse_pts(x, y, r * S, r * S * YSQ)
    }

    /// Cylindre debout (jeton, bouton, table) : base, flanc, dessus.
    fn cylinder(&self, a: f64, b: f64, z0: f64, r: f64, h: f64, top: Color, side: Color) {
        self.fill(&self.ground_ellipse(a, b, z0, r), side);
        let (xl, yt) = ground(a - r, b, z0 + h);
        let (xr, yb) = ground(a + r, b, z0);
        self.fill(&[(xl, yt), (xr, yt), (xr, yb), (xl, yb)], side);
        let t = self.ground_ellipse(a, b, z0 + h, r);
        self.fill(&t, top);
        self.outline(&t, side, 0.6);
    }

    /// Texte à plat. y = haut du texte ; align 0 gauche, 0.5 centré, 1 droite ; squash = écrasement vertical.
    fn text(&self, s: &str, x: f64, y: f64, size: f32, bold: bool, c: Color, align: f32, squash: f32) {
        let font = if bold { self.fonts.bold.as_ref() } else { self.fonts.semi.as_ref() };
        let px = (size * self.v.sc).round().max(1.0) as u16;
        let dim = measure_text(s, font, px, 1.0);
        let p = self.v.pt(x, y);
        draw_text_ex(
            s,
            p.x - dim.width * align,
            p.y + dim.offset_y * squash,
            TextParams {
                font,
                font_size: px,
                font_scale: squash,
                font_scale_aspect: 1.0 / squash,
                color: c,
                ..Default::default()
            },
        );
    }

    /// Texte couché sur le plateau, centré en (a, b) à la hauteur z.
    fn ground_text(&self, s: &str, a: f64, b: f64, z: f64, size: f32, c: Color) {
        let (x, y) = ground(a, b, z);
        self.text(s, x, y, size, true, c, 0.5, YSQ as f32);
    }
}

fn hull(mut p: Vec<(f64, f64)>) -> Vec<(f64, f64)> {
    p.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let cross = |o: (f64, f64), a: (f64, f64), b: (f64, f64)| (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0);
    let mut h: Vec<(f64, f64)> = Vec::new();
    for pass in 0..2 {
        let start = h.len();
        let it: Box<dyn Iterator<Item = &(f64, f64)>> =
            if pass == 0 { Box::new(p.iter()) } else { Box::new(p.iter().rev()) };
        for &q in it {
            while h.len() >= start + 2 && cross(h[h.len() - 2], h[h.len() - 1], q) <= 0.0 {
                h.pop();
            }
            h.push(q);
        }
        h.pop();
    }
    h
}

// ---------- dés ----------

/// Repère de la face f dans le monde : (n, a, b).
fn face_frame(d: &Die, f: usize) -> [[f64; 3]; 3] {
    [mv3(&d.w, &FACES[f][0]), mv3(&d.w, &FACES[f][1]), mv3(&d.w, &FACES[f][2])]
}

fn face_pt(d: &Die, fr: &[[f64; 3]; 3], kn: f64, ka: f64, kb: f64) -> [f64; 3] {
    std::array::from_fn(|i| d.p[i] + DIE_H * (kn * fr[0][i] + ka * fr[1][i] + kb * fr[2][i]))
}

fn draw_die_shadow(pen: &Pen, d: &Die) {
    let fr = face_frame(d, 0);
    let mut pts = Vec::with_capacity(8);
    for k in 0..8 {
        let s = |b: usize| if k >> b & 1 == 1 { 1.0 } else { -1.0 };
        let p = face_pt(d, &fr, s(2), s(0), s(1));
        pts.push(proj([p[0] + p[2] * 0.625, p[1] - p[2] * 0.3125, 0.0]));
    }
    pen.fill(&hull(pts), Color::new(0.0, 0.0, 0.0, 100.0 / 255.0));
}

fn draw_die(pen: &Pen, d: &Die) {
    for f in 0..6 {
        let fr = face_frame(d, f);
        let n = fr[0];
        if n[0] + n[1] - n[2] >= 0.0 {
            continue; // face cachée
        }
        let l = (n[0] * -0.512 + n[1] * 0.256 + n[2] * 0.82).max(0.0) * 0.55 + 0.45;
        let fill = Color::new((246.0 * l / 255.0) as f32, (240.0 * l / 255.0) as f32, (224.0 * l / 255.0) as f32, 1.0);
        let corners: Vec<(f64, f64)> = [(-1., -1.), (1., -1.), (1., 1.), (-1., 1.)]
            .iter()
            .map(|&(a, b)| proj(face_pt(d, &fr, 1.0, a, b)))
            .collect();
        pen.fill(&corners, fill);
        pen.outline(&corners, if d.held { C_GOLD } else { C_EDGE }, if d.held { 1.6 } else { 0.8 });
        let pip = if f == 0 { C_PIPRED } else { C_PIP };
        for k in 0..9 {
            if PIPMASK[f] >> k & 1 == 0 {
                continue;
            }
            let ring: Vec<(f64, f64)> = (0..16)
                .map(|j| {
                    let t = j as f64 * std::f64::consts::TAU / 16.0;
                    proj(face_pt(d, &fr, 1.004, PIPX[k] + 0.2 * t.cos(), PIPY[k] + 0.2 * t.sin()))
                })
                .collect();
            pen.fill(&ring, pip);
        }
    }
}

fn draw_dice(pen: &Pen, g: &Game) {
    for d in g.dice.iter().filter(|d| d.held) {
        let e = pen.ground_ellipse(d.ax, d.by, FELT, 1.4);
        pen.fill(&e, C_HELDDISC);
        pen.outline(&e, C_GOLD, 1.0);
    }
    let mut order: Vec<&Die> = g.dice.iter().collect();
    order.sort_by(|a, b| b.depth.partial_cmp(&a.depth).unwrap());
    for d in &order {
        draw_die_shadow(pen, d);
    }
    for d in &order {
        draw_die(pen, d);
    }
}

// ---------- table, jetons, boutons ----------

fn draw_table(pen: &Pen) {
    pen.fill(&pen.ground_ellipse(0.0, 0.0, -0.95, 8.2), C_FLOORSH);
    pen.cylinder(0.0, 0.0, -0.95, 7.0, 1.05, C_WOOD, C_WOODSIDE);
    for k in 0..16u32 {
        let c = rgb((10 + k * 18 / 15) as u8, (70 + k * 58 / 15) as u8, (44 + k * 36 / 15) as u8);
        pen.fill(&pen.ground_ellipse(0.0, 0.0, FELT, 6.35 * (1.0 - 0.07 * k as f64)), c);
    }
    pen.outline(&pen.ground_ellipse(0.0, 0.0, FELT, 6.35), C_WOODLINE, 1.0);
    for (a, b) in [(POT_A, 0.0), (0.0, PL_Z), (0.0, BOT_Z)] {
        pen.outline(&pen.ground_ellipse(a, b, FELT, 1.5), C_ZONE, 1.0);
    }
}

/// Piles de 6 jetons (8 au-delà de 12, pot de 21).
fn draw_chips(pen: &Pen, a0: f64, b: f64, n: u32, top: Color, side: Color) {
    if n == 0 {
        return;
    }
    let hs = if n > 12 { 8 } else { 6 };
    let stacks = n.div_ceil(hs);
    for j in 0..stacks {
        let a = a0 + (j as f64 - (stacks as f64 - 1.0) * 0.5) * 1.2;
        for i in 0..(n - j * hs).min(hs) {
            pen.cylinder(a, b, FELT + i as f64 * 0.17, 0.5, 0.17, top, side);
        }
    }
}

fn draw_button(pen: &Pen, b: f64, label: &str, active: bool, blue: bool) {
    let ((top, side), txt) = match (active, blue) {
        (false, _) => (C_BTNX, C_BTNTXTX),
        (true, false) => (C_BTNG, C_BTNTXT),
        (true, true) => (C_BTNB, C_BTNTXT),
    };
    pen.cylinder(BTN_A, b, FELT, 1.0, 0.30, top, side);
    pen.ground_text(label, BTN_A, b - 0.18, BTN_TZ, 23.0, txt);
}

fn draw_buttons(pen: &Pen, g: &Game) {
    let can = g.can_act();
    let (label, active) = match g.phase {
        _ if !can => ("...", false),
        Phase::PreRoll => ("LANCER", true),
        Phase::Choose => ("RELANCER", true),
        Phase::Result => ("SUIVANT", true),
        Phase::Over => ("REJOUER", true),
        _ => ("...", false),
    };
    draw_button(pen, BTN_B[0], label, active, false);
    draw_button(pen, BTN_B[1], "VALIDER", g.phase == Phase::Choose && can, true);
}

fn draw_hud(pen: &Pen, g: &Game) {
    pen.ground_text(&format!("POT {}", g.pot), POT_A, 0.95, FELT, 40.0, C_TXTGND);
    pen.ground_text(&format!("{} {}", g.label(0), g.tok[0]), 0.0, 5.4, FELT, 40.0, C_TXTGND);
    pen.ground_text(&format!("{} {}", g.label(1), g.tok[1]), 0.0, -6.0, FELT, 40.0, C_TXTGND);
    pen.text("421", 20.0, 3.0, 42.0, true, C_GOLD, 0.0, 1.0);
    let right = match g.mode {
        crate::game::Mode::Solo => format!(
            "Manche {}   -   Bot {}   -   {} - {}",
            g.round,
            ai::LEVEL_NAMES[g.level],
            g.wins,
            g.losses
        ),
        crate::game::Mode::Duo => format!("Manche {}   -   2 joueurs", g.round),
        crate::game::Mode::Online { .. } => format!("Manche {}   -   En ligne", g.round),
    };
    pen.text(&right, WW as f64 - 20.0, 17.0, 30.0, false, C_WHITE, 1.0, 1.0);
    pen.text(&g.line1, 20.0, 62.0, 30.0, false, C_WHITE, 0.0, 1.0);
    pen.text(&g.line2, 20.0, 98.0, 30.0, false, C_GOLD, 0.0, 1.0);
    pen.text(HINT, 20.0, WH as f64 - 38.0, 23.0, true, C_HINT, 0.0, 1.0);
}

/// Dessine toute l'image.
pub fn draw(g: &Game, v: View, fonts: &Fonts) {
    clear_background(BLACK);
    let pen = Pen { v, fonts };
    draw_rectangle(v.ox, v.oy, WW * v.sc, WH * v.sc, C_BG);
    draw_table(&pen);
    draw_hud(&pen, g);
    draw_chips(&pen, 0.0, BOT_Z, g.tok[1], C_BOTTOP, C_BOTSIDE);
    draw_chips(&pen, POT_A, 0.0, g.pot, C_POTTOP, C_POTSIDE);
    draw_buttons(&pen, g);
    draw_dice(&pen, g);
    draw_chips(&pen, 0.0, PL_Z, g.tok[0], C_PLTOP, C_PLSIDE);
}

// ---------- clics ----------

pub enum Hit {
    Main,
    Second,
    Die(usize),
    Nothing,
}

/// Ce qui se trouve sous le point (coordonnées du jeu).
pub fn hit(g: &Game, x: f64, y: f64) -> Hit {
    for (k, &b) in BTN_B.iter().enumerate() {
        let (cx, cy) = ground(BTN_A, b, BTN_TZ);
        let (dx, dy) = ((x - cx) / S, (y - cy) / (S * YSQ));
        if dx * dx + dy * dy <= 1.0 {
            return if k == 0 { Hit::Main } else { Hit::Second };
        }
    }
    if g.phase == Phase::Choose {
        for i in 0..3 {
            let (px, py) = proj(g.dice[g.cur * 3 + i].p);
            if (px - x).powi(2) + (py - y).powi(2) <= 3900.0 {
                return Hit::Die(i);
            }
        }
    }
    Hit::Nothing
}
