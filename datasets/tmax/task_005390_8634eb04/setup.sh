#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest flask

    mkdir -p /app/bin

    cat << 'EOF' > /app/bin/oracle
#!/usr/bin/env python3
import sys
import math

def main():
    atoms = []
    for line in sys.stdin:
        parts = line.strip().split()
        if len(parts) >= 5 and parts[0] == 'ATOM':
            try:
                x, y, z = float(parts[2]), float(parts[3]), float(parts[4])
                atoms.append((x, y, z))
            except ValueError:
                pass

    n = len(atoms)
    degrees = [0] * n
    for i in range(n):
        for j in range(i + 1, n):
            dx = atoms[i][0] - atoms[j][0]
            dy = atoms[i][1] - atoms[j][1]
            dz = atoms[i][2] - atoms[j][2]
            dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            if dist < 1.0:
                degrees[i] += 1
                degrees[j] += 1

    terms = [1.0 / (d + 1.0) for d in degrees]
    terms.sort()

    total = sum(terms)
    print(f"{total:.8f}")

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/bin/oracle

    cat << 'EOF' > /app/api.py
from flask import Flask, request

app = Flask(__name__)

# TODO: Implement /calc endpoint

if __name__ == '__main__':
    pass
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
