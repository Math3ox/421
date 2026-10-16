"""Joue une partie complète en mode terminal (421.exe -t) en répondant aux invites. Usage : python termtest.py"""
import subprocess, threading, time, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
p = subprocess.Popen([os.path.join(HERE, '421.exe'), '-t'], cwd=HERE, stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
buf = bytearray()


def reader():
    while True:
        b = p.stdout.read(1)
        if not b:
            break
        buf.extend(b)


threading.Thread(target=reader, daemon=True).start()
seen = {'press': 0, 'ask': 0, 'again': 0}
n_ask = 0
t0 = time.time()
while time.time() - t0 < 240 and p.poll() is None:
    txt = buf.decode('utf8', 'replace')
    for key, marker, reply in (('press', '[Entrée]', None), ('ask', 'Relancer quels', None), ('again', 'Rejouer ?', None)):
        c = txt.count('pour lancer les dés') if key == 'press' else txt.count(marker if key != 'ask' else 'Relancer quels dés')
        if c > seen[key]:
            seen[key] = c
            time.sleep(0.15)
            if key == 'press':
                p.stdin.write(b'\n')
            elif key == 'ask':
                n_ask += 1
                p.stdin.write(b'13\n' if n_ask % 3 == 1 else (b'2\n' if n_ask % 3 == 2 else b'\n'))
            else:
                p.stdin.write(b'n\n')
            p.stdin.flush()
    time.sleep(0.1)
try:
    p.wait(timeout=5)
except Exception:
    p.kill()
txt = buf.decode('utf8', 'replace')
clean = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', txt)
lines = [l for l in clean.split('\n') if not l.lstrip().startswith(('┌', '│', '└'))]
print('\n'.join(lines[-45:]))
print('--- code de sortie', p.returncode, '| manches vues :', clean.count('══════ Manche'), '| invites :', seen)
