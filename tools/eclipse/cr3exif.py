import struct, glob, os, json, sys

TYPESZ = {1:1,2:1,3:2,4:4,5:8,6:1,7:1,8:2,9:4,10:8,11:4,12:8}

def read_ifd(buf, off, endian='<'):
    out = {}
    if off + 2 > len(buf): return out, 0
    n, = struct.unpack_from(endian+'H', buf, off)
    for i in range(n):
        e = off + 2 + i*12
        if e+12 > len(buf): break
        tag, typ, cnt = struct.unpack_from(endian+'HHI', buf, e)
        sz = TYPESZ.get(typ, 0) * cnt
        if sz == 0: continue
        if sz <= 4:
            data = buf[e+8:e+8+sz]
        else:
            po, = struct.unpack_from(endian+'I', buf, e+8)
            data = buf[po:po+sz]
        if len(data) < sz: continue
        try:
            if typ == 2:
                val = data.split(b'\x00')[0].decode('ascii','replace')
            elif typ == 3:
                val = list(struct.unpack(endian+'%dH'%cnt, data))
            elif typ == 4:
                val = list(struct.unpack(endian+'%dI'%cnt, data))
            elif typ == 5:
                r = struct.unpack(endian+'%dI'%(cnt*2), data)
                val = [(r[j*2], r[j*2+1]) for j in range(cnt)]
            elif typ == 9:
                val = list(struct.unpack(endian+'%di'%cnt, data))
            elif typ == 10:
                r = struct.unpack(endian+'%di'%(cnt*2), data)
                val = [(r[j*2], r[j*2+1]) for j in range(cnt)]
            else:
                val = data
        except struct.error:
            continue
        if isinstance(val, list) and len(val) == 1: val = val[0]
        out[tag] = val
    nxt, = struct.unpack_from(endian+'I', buf, off + 2 + n*12) if off+2+n*12+4 <= len(buf) else (0,)
    return out, nxt

def box(data, name):
    i = data.find(name)
    if i < 4: return None
    size, = struct.unpack_from('>I', data, i-4)
    return data[i+4 : i-4+size]

def tiff(payload):
    if not payload or payload[:2] not in (b'II', b'MM'): return {}
    endian = '<' if payload[:2] == b'II' else '>'
    off, = struct.unpack_from(endian+'I', payload, 4)
    d, _ = read_ifd(payload, off, endian)
    return d

def rat(v):
    if isinstance(v, tuple) and v[1]: return v[0]/v[1]
    return None

rows = []
files = sorted(glob.glob(sys.argv[1] + '/*.CR3'))
for f in files:
    head = open(f,'rb').read(300000)
    ifd0 = tiff(box(head, b'CMT1'))
    exif = tiff(box(head, b'CMT2'))
    gps  = tiff(box(head, b'CMT4'))
    et = rat(exif.get(33434))
    rows.append({
        'file': os.path.basename(f),
        'size': os.path.getsize(f),
        'make': ifd0.get(271), 'model': ifd0.get(272),
        'dt': exif.get(36867), 'subsec': exif.get(37521),
        'exposure': et,
        'fnumber': rat(exif.get(33437)),
        'iso': exif.get(34855),
        'focal': rat(exif.get(37386)),
        'focal35': exif.get(41989),
        'expbias': rat(exif.get(37380)),
        'meter': exif.get(37383),
        'expprog': exif.get(34850),
        'expmode': exif.get(41986),
        'wb': exif.get(41987),
        'lens': exif.get(42036),
        'body_sn': exif.get(42033),
        'lens_sn': exif.get(42037),
        'w': exif.get(40962), 'h': exif.get(40963),
        'software': ifd0.get(305),
        'gps_tags': sorted(gps.keys()),
    })
print(json.dumps(rows))
