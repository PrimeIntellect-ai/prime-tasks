#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest Pillow pytesseract

mkdir -p /app

python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,30), 'h = 0.5 / (beta + gamma)', fill=(0,0,0))
img.save('/app/step_rule.png')
"

cat << 'EOF' > /app/oracle_bin.py
#!/usr/bin/env python3
import sys

def run():
    lines = sys.stdin.read().splitlines()
    if not lines: return
    N = int(lines[0])
    E = int(lines[1])

    adj = {i: [] for i in range(N)}
    for i in range(2, 2+E):
        u, v = map(int, lines[i].split())
        adj[u].append(v)
        adj[v].append(u)

    idx = 2 + E + 1
    for i in range(idx, len(lines)):
        if not lines[i].strip(): continue
        beta, gamma = map(float, lines[i].split())

        h = 0.5 / (beta + gamma)

        S = [1.0] * N
        I = [0.0] * N
        R = [0.0] * N
        I[0] = 1.0

        failed = False
        for _ in range(50):
            new_S = S[:]
            new_I = I[:]
            new_R = R[:]
            for node in range(N):
                neighbor_I = sum(I[nbr] for nbr in adj[node])
                dS = -h * beta * S[node] * neighbor_I
                dI = h * beta * S[node] * neighbor_I - h * gamma * I[node]
                dR = h * gamma * I[node]

                new_S[node] += dS
                new_I[node] += dI
                new_R[node] += dR

            S = new_S
            I = new_I
            R = new_R

            if any(x < 0 for x in S) or any(x < 0 for x in I) or any(x < 0 for x in R):
                failed = True
                break

        if failed:
            print('0')
        else:
            total_I = sum(I)
            if 0.5 < total_I < 5.0:
                print('1')
            else:
                print('0')

if __name__ == '__main__':
    run()
EOF

chmod +x /app/oracle_bin.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
