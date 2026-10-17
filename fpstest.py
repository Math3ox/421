"""Fluidité en plein écran : images/s pendant l'animation d'un lancer. Usage: python fpstest.py"""
import ctypes, os, sys, time
sys.argv = ['x', '0']
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'nettest.py'), encoding='utf8').read().split("A = Inst('A'); B = Inst('B')")[0])
W, H = user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)
s = min(W / 1100, H / 800); ox, oy = int((W - 1100 * s) / 2), int((H - 800 * s) / 2)
A = Inst('F'); time.sleep(1.0)
A.key(0x7A); time.sleep(1.2)
def frames():
    buf = ctypes.create_unicode_buffer(300); A.key(0x44); time.sleep(0.05); user32.GetWindowTextW(A.h, buf, 300)
    f = buf.value.split(); return int(f[-1]), buf.value
x, y = int(863 * s) + ox, int(393 * s) + oy
f0, _ = frames(); t0 = time.perf_counter()
user32.PostMessageW(A.h, 0x201, 1, (y << 16) | x)
time.sleep(0.9)
f1, title = frames(); t1 = time.perf_counter()
print('images pendant le lancer : %d en %.2f s = %.0f im/s' % (f1 - f0, t1 - t0, (f1 - f0) / (t1 - t0)))
print(title)
A.p.kill()
