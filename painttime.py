"""Mesure le temps d'un repaint complet (RedrawWindow synchrone) en fenetre puis en plein ecran. Usage: python painttime.py [exe]"""
import ctypes, os, shutil, subprocess, sys, time
user32 = ctypes.windll.user32; user32.SetProcessDPIAware()
exe = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '421.exe')
d = os.path.join(os.environ['TEMP'], 'pt421'); shutil.rmtree(d, ignore_errors=True); os.makedirs(d); shutil.copy(exe, d)
p = subprocess.Popen([os.path.join(d, '421.exe')], cwd=d)
from ctypes import wintypes
h = 0
for _ in range(60):
    h = user32.FindWindowA(b'Dice421Win', None)
    if h: break
    time.sleep(0.1)
time.sleep(1.0)
def meas(tag):
    ts = []
    for _ in range(15):
        t = time.perf_counter(); user32.RedrawWindow(h, None, None, 0x1 | 0x100); ts.append((time.perf_counter() - t) * 1000)
    ts.sort(); print(tag, 'repaint median %.1f ms, max %.1f ms' % (ts[len(ts) // 2], ts[-1]))
meas('fenetre')
user32.PostMessageW(h, 0x100, 0x7A, 0); time.sleep(1.5)
meas('plein ecran')
p.kill()
