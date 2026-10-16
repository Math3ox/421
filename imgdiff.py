"""Compare deux PNG : python imgdiff.py a.png b.png  ->  nombre de pixels différents, écart max, boîte."""
import struct, sys, zlib


def rd(p):
    d = open(p, 'rb').read(); pos = 8; idat = b''; w = h = 0
    while pos < len(d):
        n = struct.unpack('>I', d[pos:pos + 4])[0]; t = d[pos + 4:pos + 8]; b = d[pos + 8:pos + 8 + n]
        if t == b'IHDR':
            w, h = struct.unpack('>II', b[:8])
        elif t == b'IDAT':
            idat += b
        pos += 12 + n
    raw = zlib.decompress(idat); s = w * 3 + 1
    return w, h, [raw[i * s + 1:(i + 1) * s] for i in range(h)]


w, h, a = rd(sys.argv[1])
_, _, b = rd(sys.argv[2])
diff = 0; mx = 0; box = [w, h, 0, 0]
for y in range(h):
    if a[y] != b[y]:
        ra, rb = a[y], b[y]
        for x in range(w):
            pa, pb = ra[x * 3:x * 3 + 3], rb[x * 3:x * 3 + 3]
            if pa != pb:
                diff += 1
                mx = max(mx, max(abs(pa[i] - pb[i]) for i in range(3)))
                box = [min(box[0], x), min(box[1], y), max(box[2], x), max(box[3], y)]
print('pixels differents: %d, ecart max %d, boite %s' % (diff, mx, box))
