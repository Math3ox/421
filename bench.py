"""Banc d'essai : python bench.py [mode 1-4 | auto]
Lance 421.exe, choisit le mode (touches 1-4), mesure CPU au repos / pendant un lancer, temps par image,
mémoire, et vérifie que le rendu par zones modifiées est identique à une image complète (touche F)."""
import ctypes, subprocess, sys, os, time, statistics, struct, zlib
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
user32 = ctypes.windll.user32
k32 = ctypes.windll.kernel32
user32.SetProcessDPIAware()
F = 10_000_000
SHOT = os.path.join(HERE, '421_shot.bmp')


def bmp(path):
    d = open(path, 'rb').read()
    off = struct.unpack_from('<I', d, 10)[0]
    return d[off:]


class PMC(ctypes.Structure):
    _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD),
                ('PeakWorkingSetSize', ctypes.c_size_t), ('WorkingSetSize', ctypes.c_size_t),
                ('QuotaPeakPagedPoolUsage', ctypes.c_size_t), ('QuotaPagedPoolUsage', ctypes.c_size_t),
                ('QuotaPeakNonPagedPoolUsage', ctypes.c_size_t), ('QuotaNonPagedPoolUsage', ctypes.c_size_t),
                ('PagefileUsage', ctypes.c_size_t), ('PeakPagefileUsage', ctypes.c_size_t)]


def run(mode):
    exe = os.path.join(HERE, '421.exe')
    p = subprocess.Popen([exe], cwd=HERE)
    hwnd = 0
    for _ in range(80):
        hwnd = user32.FindWindowW('Dice421Win', None)
        if hwnd:
            break
        time.sleep(0.1)
    k32.OpenProcess.restype = wintypes.HANDLE
    h = k32.OpenProcess(0x1000 | 0x0400, False, p.pid)

    def cpu():
        c, e, k, u = (wintypes.FILETIME() for _ in range(4))
        k32.GetProcessTimes(h, ctypes.byref(c), ctypes.byref(e), ctypes.byref(k), ctypes.byref(u))
        t = lambda f: (f.dwHighDateTime << 32 | f.dwLowDateTime) / 1e7
        return t(k) + t(u)

    def vals():
        buf = ctypes.create_unicode_buffer(256)
        user32.PostMessageW(hwnd, 0x100, 0x44, 0)
        time.sleep(0.1)
        user32.GetWindowTextW(hwnd, buf, 256)
        f = [int(x) for x in buf.value.split()]
        return dict(mode=f[-4], tfr=f[-3] / F * 1000, tbg=f[-2] / F * 1000, frames=f[-1], phase=f[6])

    def shot():
        if os.path.exists(SHOT):
            os.remove(SHOT)
        user32.PostMessageW(hwnd, 0x100, 0x7B, 0)
        time.sleep(0.5)
        return bmp(SHOT)

    time.sleep(0.8)
    if mode != 'auto':
        user32.PostMessageW(hwnd, 0x100, 0x30 + int(mode), 0)
    time.sleep(1.0)
    pm = PMC(); pm.cb = ctypes.sizeof(pm)
    k32.K32GetProcessMemoryInfo(h, ctypes.byref(pm), pm.cb)
    mem = pm.WorkingSetSize / 1048576
    v0 = vals()
    c0 = cpu(); t0 = time.time(); time.sleep(3.0)
    idle = 100 * (cpu() - c0) / (time.time() - t0)
    v1 = vals()
    # un lancer : on échantillonne le temps par image
    c0 = cpu(); t0 = time.time(); f0 = v1['frames']
    user32.PostMessageW(hwnd, 0x100, 0x20, 0)
    tf = []
    while time.time() - t0 < 1.45:
        time.sleep(0.04)
        tf.append(vals()['tfr'])
    dt = time.time() - t0
    roll_cpu = 100 * (cpu() - c0) / dt
    time.sleep(1.2)
    v2 = vals()
    frames = v2['frames'] - f0
    a = shot()
    user32.PostMessageW(hwnd, 0x100, 0x46, 0)       # F : image complète
    time.sleep(0.6)
    b = shot()
    same = (a == b)
    k32.K32GetProcessMemoryInfo(h, ctypes.byref(pm), pm.cb)
    mem2 = pm.WorkingSetSize / 1048576
    user32.PostMessageW(hwnd, 0x100, 0x1B, 0)
    time.sleep(0.4)
    if p.poll() is None:
        p.kill()
    return dict(mode=v2['mode'] + 1, mem=mem2, idle=idle, roll_cpu=roll_cpu, frames=frames,
                med=statistics.median(tf) if tf else 0, mx=max(tf) if tf else 0, tbg=v1['tbg'], same=same)


modes = sys.argv[1:] or ['1', '2', '3', '4']
for m in modes:
    r = run(m)
    print('mode %d | memoire %.1f Mo | CPU repos %.1f %% | lancer: %d images, CPU %.0f %%, image mediane %.2f ms (max %.2f) | '
          'decor %.1f ms | zones==complet: %s' % (r['mode'], r['mem'], r['idle'], r['frames'], r['roll_cpu'], r['med'], r['mx'],
                                                    r['tbg'], 'OUI' if r['same'] else 'NON'))
