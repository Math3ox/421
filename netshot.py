"""Captures de l'interface en ligne (menus, saisie de l'IP, écrans des deux joueurs) et cas d'erreur."""
import os, sys, time
sys.argv = ['x', '0']
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'nettest.py'), encoding='utf8').read()
head = src.split("A = Inst('A'); B = Inst('B')")[0]
exec(head)
sys.path.insert(0, HERE)
from tools import read_png  # noqa: F401  (outil de recadrage déjà fourni)


def shot(inst, name, wait=0.5):
    f = os.path.join(os.path.dirname(inst.p.args[0]), '421_shot.bmp')
    if os.path.exists(f):
        os.remove(f)
    inst.key(0x7B)
    time.sleep(wait)
    import struct, zlib
    d = open(f, 'rb').read()
    off = struct.unpack_from('<I', d, 10)[0]
    w, h = struct.unpack_from('<ii', d, 18); h = abs(h)
    rows = []
    for y in range(h):
        r = d[off + y * w * 4: off + (y + 1) * w * 4]
        b = bytearray(w * 3); b[0::3] = r[2::4]; b[1::3] = r[1::4]; b[2::3] = r[0::4]
        rows.append(b'\x00' + bytes(b))

    def ch(t, c):
        x = struct.pack('>I', len(c)) + t + c
        return x + struct.pack('>I', zlib.crc32(t + c) & 0xffffffff)
    open(os.path.join(HERE, name), 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                                               + ch(b'IDAT', zlib.compress(b''.join(rows), 6)) + ch(b'IEND', b''))
    print('ok', name)


A = Inst('A'); B = Inst('B')
time.sleep(1.0)
A.key(0x4E); time.sleep(0.4); shot(A, 'n1_menu.png')
A.key(0x48); time.sleep(0.6); shot(A, 'n2_hote.png')
B.key(0x4E); time.sleep(0.3); B.key(0x52); time.sleep(0.3)
for c in '192.168.1.2':
    B.char(c); time.sleep(0.03)
shot(B, 'n3_saisie.png')
for _ in range(11):
    B.char(8)
for c in '127.0.0.1':
    B.char(c); time.sleep(0.03)
B.char(13); time.sleep(2.0)
shot(A, 'n4_hote_pret.png'); shot(B, 'n5_invite_pret.png')
A.click(863, 393); time.sleep(2.4)                       # l'hôte lance
shot(A, 'n6_hote_choix.png'); shot(B, 'n7_invite_attend.png')
for i in (A, B):
    i.p.kill()

# erreurs : IP invalide, port fermé
C = Inst('C'); time.sleep(1.0)
C.key(0x4E); time.sleep(0.3); C.key(0x52); time.sleep(0.3)
for c in '999.1.1.1':
    C.char(c)
C.char(13); time.sleep(0.6); shot(C, 'n8_ipinvalide.png')
C.key(0x4E); time.sleep(0.3); C.key(0x52); time.sleep(0.3)
for _ in range(12):
    C.char(8)
for c in '127.0.0.1:4299':
    C.char(c)
C.char(13); time.sleep(2.5); shot(C, 'n9_refuse.png')
C.p.kill()
