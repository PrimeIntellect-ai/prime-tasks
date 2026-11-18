import sys
import json

def parse():
    raw = sys.stdin.buffer.read()
    text = raw.decode('cp1252')
    lines = text.splitlines()

    data = {}
    for line in lines:
        line = line.strip()
        if not line or line.startswith('['):
            continue
        if '|' in line:
            k, v = line.split('|', 1)
            if k.startswith('SECURE_'):
                v = v[::-1]
            data[k] = v

    print(json.dumps(data, separators=(',', ':')))

if __name__ == '__main__':
    parse()
