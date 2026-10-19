//! Duel en ligne à 2 joueurs, connexion TCP directe par IP.
//!
//! Principe « lockstep » : les deux PC exécutent la même partie (game.rs) avec la même graine,
//! envoyée par l'hôte à la connexion. Seules les actions des joueurs circulent (12 octets chacune) ;
//! celles de l'adversaire sont appliquées quand ce PC est « posé » (dés immobiles), ce qui absorbe
//! les décalages d'animation entre les machines. L'hôte est le joueur 1, l'invité le joueur 2.

use crate::game::{Frame, Game, NK_HELLO, NK_MAIN, NK_NEW};
use std::io::{ErrorKind, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream, UdpSocket};
use std::sync::mpsc::{self, Receiver, TryRecvError};
use std::time::Duration;

pub const PORT: u16 = 4210;

enum State {
    Off,
    Listening(TcpListener),
    Connecting(Receiver<std::io::Result<TcpStream>>),
    Connected(TcpStream),
}

#[derive(PartialEq)]
pub enum Menu {
    None,
    Choice,
    Ip,
}

pub struct Net {
    state: State,
    pub menu: Menu,
    /// dernière adresse saisie (mémorisée dans 421.cfg)
    pub ip: String,
    rx: Vec<u8>,
    saved: (String, String),
    /// mode local à retrouver après une partie en ligne
    prev_duo: bool,
}

pub fn encode(f: &Frame) -> [u8; 12] {
    let mut b = [0u8; 12];
    b[0] = f.kind;
    b[1] = f.b1;
    b[2..4].copy_from_slice(&f.b.to_le_bytes());
    b[4..8].copy_from_slice(&f.c.to_le_bytes());
    b[8..12].copy_from_slice(&f.d.to_le_bytes());
    b
}

pub fn decode(b: &[u8]) -> Frame {
    Frame {
        kind: b[0],
        b1: b[1],
        b: u16::from_le_bytes([b[2], b[3]]),
        c: u32::from_le_bytes([b[4], b[5], b[6], b[7]]),
        d: u32::from_le_bytes([b[8], b[9], b[10], b[11]]),
    }
}

/// Adresse IP locale principale (celle qu'un ami du réseau local doit taper).
fn local_ip() -> String {
    UdpSocket::bind("0.0.0.0:0")
        .and_then(|s| {
            s.connect("192.0.2.1:9")?;
            s.local_addr()
        })
        .map(|a| a.ip().to_string())
        .unwrap_or_else(|_| "?".into())
}

/// « ip » ou « ip:port » -> adresse (port 4210 par défaut).
pub fn parse_addr(s: &str) -> Option<SocketAddr> {
    let (ip, port) = match s.split_once(':') {
        Some((ip, p)) => (ip, p.parse::<u16>().ok().filter(|&p| p != 0)?),
        None => (s, PORT),
    };
    let ip: std::net::Ipv4Addr = ip.parse().ok()?;
    if ip.is_unspecified() {
        return None;
    }
    Some(SocketAddr::from((ip, port)))
}

impl Net {
    pub fn new(ip: String) -> Net {
        Net { state: State::Off, menu: Menu::None, ip, rx: Vec::new(), saved: Default::default(), prev_duo: false }
    }

    /// Attente d'un ami ou connexion en cours (Échap annule).
    pub fn pending(&self) -> bool {
        matches!(self.state, State::Listening(_) | State::Connecting(_))
    }

    pub fn active(&self) -> bool {
        !matches!(self.state, State::Off)
    }

    /// Touche N : ouvre le menu, ou coupe la connexion en cours.
    pub fn open(&mut self, g: &mut Game) {
        if self.active() {
            self.close(g, "Multijoueur annulé.");
            return;
        }
        if self.menu != Menu::None {
            return;
        }
        self.saved = (g.line1.clone(), g.line2.clone());
        self.menu = Menu::Choice;
        g.line1 = "Multijoueur : H = héberger une partie, R = rejoindre (Échap = annuler)".into();
        g.line2 = "Les deux joueurs doivent avoir la même version du jeu.".into();
    }

    fn restore(&mut self, g: &mut Game) {
        (g.line1, g.line2) = self.saved.clone();
        self.menu = Menu::None;
    }

    /// Touche pendant le menu « H / R ».
    pub fn menu_key(&mut self, g: &mut Game, c: char) {
        match c.to_ascii_uppercase() {
            'H' => {
                self.menu = Menu::None;
                self.host(g);
            }
            'R' => {
                self.menu = Menu::Ip;
                self.prompt(g);
            }
            _ => self.restore(g),
        }
    }

    fn prompt(&self, g: &mut Game) {
        g.line1 = format!("Adresse IP de l'hôte (Entrée = valider) : {}_", self.ip);
        g.line2 = "Exemple : 192.168.1.20   (autre port : 192.168.1.20:4210). Échap = annuler.".into();
    }

    /// Saisie de l'adresse : caractère tapé. Renvoie vrai si l'adresse a changé (à mémoriser).
    pub fn ip_char(&mut self, g: &mut Game, c: char) -> bool {
        match c {
            '\u{1b}' => self.restore(g),
            '\r' | '\n' => return self.join(g),
            '\u{8}' => {
                self.ip.pop();
                self.prompt(g);
            }
            '0'..='9' | '.' | ':' if self.ip.len() < 21 => {
                self.ip.push(c);
                self.prompt(g);
            }
            _ => {}
        }
        false
    }

    fn host(&mut self, g: &mut Game) {
        let l = TcpListener::bind(("0.0.0.0", PORT)).and_then(|l| {
            l.set_nonblocking(true)?;
            Ok(l)
        });
        match l {
            Ok(l) => {
                self.state = State::Listening(l);
                g.line1 = format!("En attente d'un ami... Ton IP : {}", local_ip());
                g.line2 = "Port 4210 (réseau local, VPN ou redirection de port). Échap = annuler.".into();
            }
            Err(_) => g.line1 = "Impossible d'écouter sur le port 4210 (déjà utilisé ?).".into(),
        }
    }

    fn join(&mut self, g: &mut Game) -> bool {
        let Some(addr) = parse_addr(&self.ip) else {
            self.prompt(g);
            g.line2 = "Adresse IP invalide. Exemple : 192.168.1.20".into();
            return false;
        };
        self.menu = Menu::None;
        let (tx, rx) = mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(TcpStream::connect_timeout(&addr, Duration::from_secs(8)));
        });
        self.state = State::Connecting(rx);
        g.line1 = "Connexion en cours... (Échap = annuler)".into();
        g.line2.clear();
        true
    }

    /// Ferme la connexion ; une partie en ligne laisse place à une nouvelle partie locale.
    pub fn close(&mut self, g: &mut Game, msg: &str) {
        self.state = State::Off;
        self.rx.clear();
        if g.online() {
            self.menu = Menu::None;
            g.leave_online(self.prev_duo);
        } else {
            self.restore(g);
        }
        g.line2 = msg.into();
    }

    fn connected(&mut self, g: &mut Game, s: TcpStream, seat: usize) {
        let _ = s.set_nodelay(true);
        let _ = s.set_nonblocking(true);
        self.state = State::Connected(s);
        self.rx.clear();
        if seat == 0 {
            // l'hôte envoie sa graine et son pot puis démarre
            let seed = g.rng;
            let hello = Frame { kind: NK_HELLO, b1: g.pot_init as u8, b: 1, c: seed as u32, d: (seed >> 32) as u32 };
            self.send(&hello);
            self.start(g, 0, seed, g.pot_init);
        } else {
            g.line1 = "Connecté ! Attente du départ de la partie...".into();
        }
    }

    fn start(&mut self, g: &mut Game, seat: usize, seed: u64, pot: u32) {
        if !g.online() {
            self.prev_duo = g.mode == crate::game::Mode::Duo;
        }
        self.menu = Menu::None;
        g.start_online(seat, seed, pot);
    }

    fn send(&mut self, f: &Frame) -> bool {
        if let State::Connected(s) = &mut self.state {
            s.write_all(&encode(f)).is_ok()
        } else {
            true
        }
    }

    /// À appeler à chaque image : connexions, réception, envoi des actions locales.
    pub fn poll(&mut self, g: &mut Game) {
        match &mut self.state {
            State::Off => {
                g.outbox.clear();
                return;
            }
            State::Listening(l) => match l.accept() {
                Ok((s, _)) => self.connected(g, s, 0),
                Err(e) if e.kind() == ErrorKind::WouldBlock => {}
                Err(_) => self.close(g, "Connexion impossible (hôte absent ou port fermé)."),
            },
            State::Connecting(rx) => match rx.try_recv() {
                Ok(Ok(s)) => self.connected(g, s, 1),
                Ok(Err(_)) | Err(TryRecvError::Disconnected) => {
                    self.close(g, "Connexion impossible (hôte absent ou port fermé).")
                }
                Err(TryRecvError::Empty) => {}
            },
            State::Connected(s) => {
                let mut buf = [0u8; 256];
                let mut lost = false;
                loop {
                    match s.read(&mut buf) {
                        Ok(0) => {
                            lost = true;
                            break;
                        }
                        Ok(n) => self.rx.extend_from_slice(&buf[..n]),
                        Err(e) if e.kind() == ErrorKind::WouldBlock => break,
                        Err(e) if e.kind() == ErrorKind::Interrupted => {}
                        Err(_) => {
                            lost = true;
                            break;
                        }
                    }
                }
                while self.rx.len() >= 12 {
                    let f = decode(&self.rx[..12]);
                    self.rx.drain(..12);
                    if f.kind == NK_HELLO {
                        if !g.online() {
                            let seed = f.c as u64 | (f.d as u64) << 32;
                            self.start(g, 1, seed, f.b1 as u32);
                        }
                    } else if (NK_MAIN..=NK_NEW).contains(&f.kind) && g.online() && g.inbox.len() < 64 {
                        g.inbox.push_back(f);
                    }
                }
                let out: Vec<Frame> = g.outbox.drain(..).collect();
                for f in &out {
                    if !self.send(f) {
                        lost = true;
                    }
                }
                if lost {
                    self.close(g, "Connexion perdue : retour à la partie locale.");
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::game::Phase;

    #[test]
    fn trames() {
        let f = Frame { kind: NK_HELLO, b1: 11, b: 1, c: 0xDEADBEEF, d: 0x01234567 };
        assert_eq!(decode(&encode(&f)), f);
        assert_eq!(parse_addr("192.168.1.20"), Some("192.168.1.20:4210".parse().unwrap()));
        assert_eq!(parse_addr("10.0.0.1:5000"), Some("10.0.0.1:5000".parse().unwrap()));
        assert_eq!(parse_addr("10.0.0"), None);
        assert_eq!(parse_addr("0.0.0.0"), None);
    }

    /// Hôte et invité sur 127.0.0.1 : vraie connexion TCP, les deux parties restent identiques.
    #[test]
    fn duel_local_tcp() {
        let mut ga = Game::new(7);
        let mut gb = Game::new(99);
        let mut a = Net::new(String::new());
        let mut b = Net::new("127.0.0.1".into());
        a.open(&mut ga);
        a.menu_key(&mut ga, 'h');
        assert!(a.pending(), "{}", ga.line1);
        b.open(&mut gb);
        b.menu_key(&mut gb, 'r');
        b.ip_char(&mut gb, '\r');
        let mut step = 0u32;
        for _ in 0..4000 {
            a.poll(&mut ga);
            b.poll(&mut gb);
            ga.tick(120.0);
            gb.tick(45.0);
            for g in [&mut ga, &mut gb] {
                if g.online() && g.idle() && g.inbox.is_empty() && g.can_act() {
                    step += 1;
                    match g.phase {
                        Phase::PreRoll | Phase::Result | Phase::Over => g.ui_main(),
                        Phase::Choose if step % 2 == 0 => g.ui_second(),
                        Phase::Choose => {
                            g.ui_toggle((step % 3) as usize);
                            g.ui_main();
                        }
                        _ => {}
                    }
                }
            }
            if ga.round >= 8 && gb.round == ga.round && ga.idle() && gb.idle() {
                break;
            }
            std::thread::sleep(Duration::from_millis(1));
        }
        assert!(ga.online() && gb.online(), "{} / {}", ga.line1, gb.line1);
        assert!(ga.round >= 8, "la partie n'a pas avancé : {}", ga.round);
        assert_eq!((ga.pot, ga.tok, ga.rng), (gb.pot, gb.tok, gb.rng));
        assert_eq!((ga.hand(0), ga.hand(1)), (gb.hand(0), gb.hand(1)));
        // l'invité part : l'hôte revient en partie locale
        b.close(&mut gb, "fin");
        for _ in 0..200 {
            a.poll(&mut ga);
            if !ga.online() {
                break;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        assert!(!ga.online());
    }
}
