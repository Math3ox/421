"""Test plein écran mis à l'échelle : capture + clic sur LANCER aux coordonnées de l'écran, puis retour fenêtre."""
import ctypes, os, subprocess, sys, time
sys.argv = ['x', '0']
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'nettest.py'), encoding='utf8').read()
exec(src.split("A = Inst('A'); B = Inst('B')")[0])
W, H = user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)
s = min(W / 1100, H / 800)
ox, oy = int((W - 1100 * s) / 2), int((H - 800 * s) / 2)
print('ecran', W, H, 'echelle %.3f' % s, 'offset', ox, oy)
A = Inst('F'); time.sleep(1.0)
rc = ctypes.create_string_buffer(16); user32.GetWindowRect(A.h, rc); print('fenetre', ctypes.c_int.from_buffer(rc, 0).value, ctypes.c_int.from_buffer(rc, 4).value, ctypes.c_int.from_buffer(rc, 8).value, ctypes.c_int.from_buffer(rc, 12).value)
A.key(0x7A); time.sleep(1.2)                       # F11
os.system(r'C:\Python313\python.exe screencap.py fs_scaled.png 2')
x, y = int(863 * s) + ox, int(393 * s) + oy
user32.PostMessageW(A.h, 0x201, 1, (y << 16) | x)  # clic LANCER (coordonnées fenêtre = écran)
time.sleep(0.3)
st = A.state(); print('apres clic : phase', st['phase'], 'pthrows', st['pthrows'], '(phase 1 = lancer attendu)')
time.sleep(2.5)
os.system(r'C:\Python313\python.exe screencap.py fs_scaled2.png 2')
A.key(0x1B); time.sleep(1.0)
user32.GetWindowRect(A.h, rc); print('retour fenetre', ctypes.c_int.from_buffer(rc, 0).value, ctypes.c_int.from_buffer(rc, 4).value, ctypes.c_int.from_buffer(rc, 8).value, ctypes.c_int.from_buffer(rc, 12).value)
st = A.state(); print('apres retour : phase', st['phase'])
A.p.kill()
