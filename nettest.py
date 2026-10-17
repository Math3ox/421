"""Test du duel en ligne : deux instances de 421.exe (hôte + invité sur 127.0.0.1) jouent 2 parties complètes ;
on vérifie que les deux côtés restent identiques (dés, phase, jetons, manche), y compris quand les deux
cliquent en même temps sur SUIVANT / REJOUER.  Usage : python nettest.py [parties=2]"""
import ctypes, os, random, shutil, subprocess, sys, time
from ctypes import wintypes

user32 = ctypes.windll.user32
user32.SetProcessDPIAware()
HERE = os.path.dirname(os.path.abspath(__file__))
GAMES = int(sys.argv[1]) if len(sys.argv) > 1 else 2
random.seed(5)


def launch(name):
    d = os.path.join(os.environ['TEMP'], 'net421_' + name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    shutil.copy(os.path.join(HERE, '421.exe'), d)
    p = subprocess.Popen([os.path.join(d, '421.exe')], cwd=d)
    return p


def window_of(pid):
    found = []
    EnumProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)

    def cb(h, _):
        pp = wintypes.DWORD()
        user32.GetWindowThreadProcessId(h, ctypes.byref(pp))
        buf = ctypes.create_unicode_buffer(64)
        user32.GetClassNameW(h, buf, 64)
        if pp.value == pid and buf.value == 'Dice421Win':
            found.append(h)
        return True
    user32.EnumWindows(EnumProc(cb), 0)
    return found[0] if found else 0


class Inst:
    def __init__(self, name):
        self.p = launch(name)
        self.h = 0
        for _ in range(80):
            self.h = window_of(self.p.pid)
            if self.h:
                break
            time.sleep(0.1)

    def key(self, vk):
        user32.PostMessageW(self.h, 0x100, vk, 0)

    def char(self, c):
        user32.PostMessageW(self.h, 0x102, ord(c) if isinstance(c, str) else c, 0)

    def click(self, x, y):
        user32.PostMessageW(self.h, 0x201, 1, (y << 16) | x)

    def state(self):
        buf = ctypes.create_unicode_buffer(300)
        self.key(0x44)
        time.sleep(0.12)
        user32.GetWindowTextW(self.h, buf, 300)
        try:
            f = [int(x) for x in buf.value.split()]
        except ValueError:
            return None
        return dict(dice=tuple(f[0:6]), phase=f[6], pthrows=f[8], lim=f[9], starter=f[10], cur=f[13], net=f[14],
                    seat=f[15], pot=f[16], ptok=f[17], btok=f[18], round=f[19], held=f[11])

    def title(self):
        buf = ctypes.create_unicode_buffer(300)
        user32.GetWindowTextW(self.h, buf, 300)
        return buf.value


A = Inst('A'); B = Inst('B')
time.sleep(1.0)
A.key(0x4E); time.sleep(0.3); A.key(0x48)             # N puis H : héberger
time.sleep(0.6)
B.key(0x4E); time.sleep(0.3); B.key(0x52)             # N puis R : rejoindre
time.sleep(0.4)
for c in '127.0.0.1':
    B.char(c); time.sleep(0.03)
B.char(13)
time.sleep(2.0)
sa, sb = A.state(), B.state()
print('connexion : A net=%s siege=%s | B net=%s siege=%s' % (sa['net'], sa['seat'], sb['net'], sb['seat']))
assert sa['net'] == 3 and sb['net'] == 3 and sa['seat'] == 0 and sb['seat'] == 1, 'connexion non etablie'

SETTLED = (0, 2, 4, 5)
SAME = ('dice', 'phase', 'cur', 'pot', 'ptok', 'btok', 'round', 'pthrows', 'lim', 'starter')
compares = mism_events = 0
mism_since = None
games_done = 0
t0 = time.time()
last_act = 0
over_acted = False
while games_done < GAMES and time.time() - t0 < 600:
    sa, sb = A.state(), B.state()
    if not sa or not sb:
        continue
    same = all(sa[k] == sb[k] for k in SAME)
    if sa['phase'] in SETTLED and sb['phase'] in SETTLED:
        compares += 1
        if not same:
            mism_since = mism_since or time.time()
            if time.time() - mism_since > 4:
                mism_events += 1
                print('DESYNC', {k: (sa[k], sb[k]) for k in SAME if sa[k] != sb[k]})
                mism_since = None
        else:
            mism_since = None
    if not (same and sa['phase'] in SETTLED and sb['phase'] in SETTLED):
        time.sleep(0.3)
        continue
    ph = sa['phase']
    actor = A if sa['cur'] == 0 else B
    seat = 0 if actor is A else 1
    if ph == 0:
        actor.click(863, 393)
        over_acted = False
    elif ph == 2:
        row = 500 if seat == 0 else 315
        if random.random() < 0.6 and sa['pthrows'] < sa['lim'] and (sa['phase'] == 2):
            actor.click(404 + 146 * random.randint(0, 2), row)       # coche un dé
            time.sleep(0.5)
            actor.click(863, 393)                                       # RELANCER
        else:
            actor.click(863, 468)                                       # VALIDER
    elif ph == 4:
        A.click(863, 393); B.click(863, 393)                            # les deux cliquent SUIVANT en même temps
    elif ph == 5:
        if not over_acted:
            games_done += 1
            print('partie %d terminee : manche %d, jetons %d/%d' % (games_done, sa['round'], sa['ptok'], sa['btok']))
            over_acted = True
            if games_done < GAMES:
                A.click(863, 393); B.click(863, 393)                    # les deux cliquent REJOUER en même temps
    time.sleep(1.6 if ph in (0, 2) else 1.0)

sa, sb = A.state(), B.state()
print('titres finaux :', A.title()[:60], '|', B.title()[:60])
print('comparaisons : %d | desynchronisations : %d | parties terminees : %d' % (compares, mism_events, games_done))
# coupure : l'hôte quitte, l'invité doit revenir en partie locale
A.key(0x1B); time.sleep(1.0)
sb = B.state()
print('apres depart de l\'hote : invite net=%s (0 attendu), 2 joueurs locaux twop restaure' % (sb['net'] if sb else None))
for i in (A, B):
    try:
        i.p.kill()
    except Exception:
        pass
