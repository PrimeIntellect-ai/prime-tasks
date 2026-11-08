import sys
from collections import defaultdict

config = defaultdict(dict)
current_section = None

try:
    with open('/home/user/base.ini', 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(';') or line.startswith('#'): continue
            if line.startswith('[') and line.endswith(']'):
                current_section = line[1:-1]
            elif '=' in line and current_section:
                k, v = line.split('=', 1)
                config[current_section][k.strip()] = v.strip()
except FileNotFoundError:
    pass

for line in sys.stdin:
    line = line.strip()
    if not line: continue
    parts = line.split(' ', 3)
    cmd = parts[0]
    if cmd == 'ADD' and len(parts) >= 4:
        sec, k, v = parts[1], parts[2], parts[3]
        config[sec][k] = v
    elif cmd == 'MOD' and len(parts) >= 4:
        sec, k, v = parts[1], parts[2], parts[3]
        if sec in config and k in config[sec]:
            config[sec][k] = v
    elif cmd == 'DEL' and len(parts) >= 3:
        sec, k = parts[1], parts[2]
        if sec in config and k in config[sec]:
            del config[sec][k]

for sec in sorted(config.keys()):
    print(f"[{sec}]")
    for k in sorted(config[sec].keys()):
        print(f"{k}={config[sec][k]}")
