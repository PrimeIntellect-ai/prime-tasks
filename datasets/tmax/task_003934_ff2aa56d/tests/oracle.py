import sys

for line in sys.stdin:
    line = line.split(';')[0]
    line = line.strip()
    if not line:
        continue
    if line == 'G28':
        print('G28 X Y')
        continue

    parts = line.split()
    if parts and parts[0] == 'M104':
        new_parts = []
        for p in parts:
            if p.startswith('S'):
                try:
                    val = int(p[1:])
                    if val > 240:
                        p = 'S240'
                except:
                    pass
            new_parts.append(p)
        print(' '.join(new_parts))
    elif parts and parts[0] == 'G1':
        new_parts = []
        for p in parts:
            if p.startswith('F'):
                try:
                    val = int(p[1:])
                    if val > 3600:
                        p = 'F3600'
                except:
                    pass
            new_parts.append(p)
        print(' '.join(new_parts))
    else:
        print(line)
