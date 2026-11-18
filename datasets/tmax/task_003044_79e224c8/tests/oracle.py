import sys
import re
import base64

last_seen = {}

for line in sys.stdin:
    match = re.match(r'^\[(\d+)\] \{([a-z0-9]+)\} - (.*)$', line.strip())
    if not match: continue
    ts = int(match.group(1))
    enc = match.group(2)
    payload = match.group(3)

    try:
        if enc == 'b64':
            decoded = base64.b64decode(payload).decode('utf-8')
        elif enc == 'hex':
            decoded = bytes.fromhex(payload).decode('utf-8')
        else:
            continue
    except:
        continue

    if '=' not in decoded: continue
    k, v = decoded.split('=', 1)

    bucket = (ts // 300) * 300

    if v == '':
        v = last_seen.get((bucket, k), "DEFAULT")
    else:
        last_seen[(bucket, k)] = v

    print(f"{bucket},{k},{v}")
