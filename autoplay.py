"""Joue une partie complète automatiquement (test) : LANCER, VALIDER, SUIVANT... jusqu'à la fin."""
import ctypes, subprocess, time, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

user32 = ctypes.windll.user32
user32.SetProcessDPIAware()
HERE = os.path.dirname(os.path.abspath(__file__))
SHOT = os.path.join(HERE, '421_shot.bmp')

p = subprocess.Popen([os.path.join(HERE, '421.exe')], cwd=HERE)
hwnd = 0
for _ in range(50):
    hwnd = user32.FindWindowW('Dice421Win', None)
    if hwnd:
        break
    time.sleep(0.1)


def click(x, y):
    user32.PostMessageW(hwnd, 0x201, 1, (y << 16) | x)


def state():
    buf = ctypes.create_unicode_buffer(160)
    user32.PostMessageW(hwnd, 0x100, 0x44, 0)
    time.sleep(0.15)
    user32.GetWindowTextW(hwnd, buf, 160)
    f = buf.value.split()
    return [int(v) for v in f[:6]], int(f[6])


t0 = time.time()
rounds = 0
last = None
while time.time() - t0 < 300:
    if p.poll() is not None:
        print('PLANTAGE, code', p.returncode)
        break
    dice, phase = state()
    if phase != last:
        print('%5.1fs phase %d dés %s' % (time.time() - t0, phase, dice))
        last = phase
    if phase == 0:
        click(863, 393)
    elif phase == 2:
        click(863, 468)
    elif phase == 4:
        rounds += 1
        click(863, 393)
    elif phase == 5:
        print('FIN DE PARTIE après', rounds, 'manches')
        if os.path.exists(SHOT):
            os.remove(SHOT)
        user32.PostMessageW(hwnd, 0x100, 0x7B, 0)
        time.sleep(0.8)
        break
    time.sleep(0.4)
if p.poll() is None:
    user32.PostMessageW(hwnd, 0x100, 0x1B, 0)
    time.sleep(0.5)
    if p.poll() is None:
        p.kill()
