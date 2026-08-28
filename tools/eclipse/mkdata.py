import json, math, datetime as dt

SKIP = {'CAR67438.CR3', 'CAR67455.CR3', 'CAR67456.CR3', 'CAR67457.CR3', 'CAR67564.CR3'}
ex = json.load(open('exif.json'))
def T(x): return dt.datetime.strptime(x['dt'], '%Y:%m:%d %H:%M:%S') + dt.timedelta(seconds=int(x['subsec']) / 100)
ex.sort(key=T)
used = [x for x in ex if x['file'] not in SKIP]
t0, t1 = T(ex[0]), T(ex[-1])
span = (t1 - t0).total_seconds()

def EV(x): return math.log2(x['fnumber'] ** 2 / x['exposure']) - math.log2(x['iso'] / 100)

def sh(t):
    if t >= 1: return f'{t:g}s'
    return '1/' + str(round(1 / t))

# clusters (bursts)
cl = [[used[0]]]
for a, b in zip(used, used[1:]):
    (cl[-1].append(b) if (T(b) - T(a)).total_seconds() <= 45 else cl.append([b]))

# photometry, clean points only
ph = json.load(open('photom.json'))
ph.sort(key=T)
clean = [x for x in ph if x['clip'] < 0.0005 and not x['edge'] and x['iso'] >= 200 and x['flux'] > 0]
ref = max(x['rad'] for x in clean)
curve = [{'t': round((T(x) - t0).total_seconds()), 'clock': T(x).strftime('%H:%M'),
          'stops': round(math.log2(x['rad'] / ref), 3)} for x in clean]

# shot log: every used frame
log = [{'t': round((T(x) - t0).total_seconds()), 'ev': round(EV(x), 2), 'iso': x['iso']} for x in used]

# stages: only what the processing filenames actually record
stages = json.load(open('stages.json'))

# bursts: straight from EXIF, no reconstruction
bursts = []
for c in cl:
    evs = [EV(f) for f in c]
    shut = sorted(set(f['exposure'] for f in c))
    bursts.append({
        'start': T(c[0]).strftime('%H:%M:%S'),
        'end': T(c[-1]).strftime('%H:%M:%S'),
        'n': len(c),
        'levels': len(set((f['exposure'], f['iso'], f['fnumber']) for f in c)),
        'stops': round(max(evs) - min(evs), 1),
        'iso': [min(f['iso'] for f in c), max(f['iso'] for f in c)],
        'shutter': [sh(shut[0]), sh(shut[-1])],
        'ap': sorted(set(f['fnumber'] for f in c)),
        'focal': sorted(set(int(f['focal']) for f in c)),
    })

data = {
    'frames': len(ex), 'used': len(used), 'excluded': len(ex) - len(used),
    'burstCount': len(cl),
    'start': t0.strftime('%H:%M:%S'), 'end': t1.strftime('%H:%M:%S'),
    'spanSec': round(span), 'spanText': f'{int(span // 60)} min {int(span % 60)} s',
    'openSec': round(sum(x['exposure'] for x in used), 2),
    'dutyPct': round(100 * sum(x['exposure'] for x in used) / span, 2),
    'bytes': sum(x['size'] for x in ex),
    'gb': round(sum(x['size'] for x in ex) / 1e9, 2),
    'isoMin': min(x['iso'] for x in used), 'isoMax': max(x['iso'] for x in used),
    'isoCount': len(set(x['iso'] for x in used)),
    'shutMin': sh(min(x['exposure'] for x in used)), 'shutMax': sh(max(x['exposure'] for x in used)),
    'shutCount': len(set(x['exposure'] for x in used)),
    'evRange': round(max(EV(x) for x in used) - min(EV(x) for x in used), 2),
    'apMin': min(x['fnumber'] for x in used), 'apMax': max(x['fnumber'] for x in used),
    'drop': round(-min(c['stops'] for c in curve), 2),
    'dropFactor': round(2 ** -min(c['stops'] for c in curve)),
    'curveFrom': curve[0]['clock'], 'curveTo': curve[-1]['clock'],
    'curvePoints': len(curve),
    'body': used[0]['model'], 'lens': used[0]['lens'],
    'sensorW': used[0]['w'], 'sensorH': used[0]['h'],
    'curve': curve, 'log': log, 'stages': stages, 'bursts': bursts,
    'bracketed': sum(1 for b in bursts if b['levels'] > 1),
    'deepest': max(bursts, key=lambda b: b['stops']),
}
json.dump(data, open('eclipse.json', 'w'), indent=1)
for k, v in data.items():
    if k not in ('curve', 'log', 'stages'): print(k, '=', v)
print('stages', len(stages), stages[0]); print('bursts', len(bursts), bursts[0])
