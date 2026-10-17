"""Compare les décisions du bot « difficile » de l'assembleur (touche T -> 421_bot.bin) à la stratégie Python (gen_tables.py)."""
import ctypes, os, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_tables as G

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '421_bot.bin')
user32 = ctypes.windll.user32
user32.SetProcessDPIAware()
if os.path.exists(OUT):
    os.remove(OUT)
p = subprocess.Popen([os.path.join(HERE, '421_dev.exe')], cwd=HERE)
hwnd = 0
for _ in range(80):
    hwnd = user32.FindWindowW('Dice421Win', None)
    if hwnd:
        break
    time.sleep(0.1)
time.sleep(0.8)
user32.PostMessageW(hwnd, 0x100, 0x54, 0)       # T
for _ in range(100):
    time.sleep(0.2)
    if os.path.exists(OUT) and os.path.getsize(OUT) >= 5616:
        break
time.sleep(0.3)
user32.PostMessageW(hwnd, 0x100, 0x1B, 0)
time.sleep(0.4)
if p.poll() is None:
    p.kill()
data = open(OUT, 'rb').read()
print('octets recus :', len(data), '(attendu 5616)')

scen = [(0, 0, 1, 3), (0, 0, 2, 3)]
for tr, tk in [(1000, 8), (900, 7), (813, 6), (806, 3), (706, 2), (665, 1), (541, 1), (1, 1)]:
    for thr, lim in ((1, 2), (1, 3), (2, 3)):
        scen.append((tr, tk, thr, lim))
bad = 0
pos = 0
for tr, tk, thr, lim in scen:
    diff = 0
    for n in range(216):
        hand = (n // 36 + 1, (n // 6) % 6 + 1, n % 6 + 1)
        if tr == 0:
            exp = G.policy_starter(hand, thr)
        else:
            exp = G.policy_follower(hand, thr, lim, tr, tk)
        got = data[pos] if pos < len(data) else -1
        pos += 1
        if got != exp:
            diff += 1
            if diff <= 2:
                print('  ecart : cible %d/%d lancers %d/%d main %s : asm=%s python=%s' % (tr, tk, thr, lim, hand, got, exp))
    bad += diff
    if diff:
        print('scenario cible=%d lancers=%d/%d : %d ecarts sur 216' % (tr, thr, lim, diff))
print('TOTAL : %d ecarts sur %d decisions' % (bad, pos))
