//! Réglages mémorisés dans `421.cfg` à côté de l'exécutable (texte « clé = valeur »).
//! Supprimer le fichier remet les valeurs par défaut ; un champ invalide est ignoré.

use crate::game::{Game, Mode};
use std::path::PathBuf;

#[derive(Default)]
pub struct Cfg {
    pub fullscreen: bool,
    pub ip: String,
}

fn path() -> Option<PathBuf> {
    std::env::current_exe().ok().map(|p| p.with_file_name("421.cfg"))
}

pub fn load(g: &mut Game) -> Cfg {
    let mut c = Cfg::default();
    let Some(text) = path().and_then(|p| std::fs::read_to_string(p).ok()) else { return c };
    for line in text.lines() {
        let Some((k, v)) = line.split_once('=') else { continue };
        let v = v.trim();
        let n = v.parse::<u32>().ok();
        match (k.trim(), n) {
            ("pot", Some(p @ (7 | 11 | 15 | 21))) => g.pot_init = p,
            ("niveau", Some(l @ 0..=2)) => g.level = l as usize,
            ("deux_joueurs", Some(1)) => g.mode = Mode::Duo,
            ("plein_ecran", Some(f @ 0..=1)) => c.fullscreen = f == 1,
            ("victoires", Some(w @ 0..=99999)) => g.wins = w,
            ("defaites", Some(l @ 0..=99999)) => g.losses = l,
            ("ip", _) if v.len() <= 21 && v.chars().all(|c| c.is_ascii_digit() || c == '.' || c == ':') => {
                c.ip = v.into()
            }
            _ => {}
        }
    }
    g.pot = g.pot_init;
    c
}

/// Écrit les réglages (silencieux si le dossier n'est pas inscriptible). Le mode en ligne n'est pas mémorisé.
pub fn save(g: &Game, c: &Cfg, duo_before_online: bool) {
    let duo = match g.mode {
        Mode::Duo => true,
        Mode::Online { .. } => duo_before_online,
        Mode::Solo => false,
    };
    let text = format!(
        "# réglages du 421 (supprimer ce fichier remet les valeurs par défaut)\n\
         pot = {}\nniveau = {}\ndeux_joueurs = {}\nplein_ecran = {}\nvictoires = {}\ndefaites = {}\nip = {}\n",
        g.pot_init, g.level, duo as u8, c.fullscreen as u8, g.wins, g.losses, c.ip
    );
    if let Some(p) = path() {
        let _ = std::fs::write(p, text);
    }
}
