#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Pillow

    mkdir -p /app
    mkdir -p /home/user

    # Generate the specification image
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """Adaptive Integration Rule for FASTA Decay:
Init: x = 100.0, t = 0.0, dt = 0.1
Loop strictly while t < 5.0:
  dx = - K * x * dt
  x = x + dx
  t = t + dt
  dt = 0.1 * (1.0 + K)

Analytical Validation:
x_exact = 100.0 * exp(-K * 5.0)"""
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/specification.png')
EOF
    python3 /tmp/make_image.py

    # Create the buggy simulator script
    cat << 'EOF' > /home/user/decay_simulator.py
import sys
import math

def calculate_gc(sequence):
    gc_count = sequence.count('G') + sequence.count('C')
    return gc_count / len(sequence) if len(sequence) > 0 else 0

def main():
    lines = sys.stdin.read().splitlines()
    seq = "".join([l for l in lines if not l.startswith(">")])
    K = calculate_gc(seq)

    # Buggy constant step size integration
    x = 100.0
    t = 0.0
    dt = 0.1
    while t < 5.0:
        dx = - K * x * dt
        x = x + dx
        t = t + dt
        # Missing step size adaptation

    x_exact = 100.0 * math.exp(-K * 5.0)
    print(f"{x:.4f} {x_exact:.4f}")

if __name__ == "__main__":
    main()
EOF

    # Create the oracle binary
    cat << 'EOF' > /app/oracle_bin
#!/usr/bin/env python3
import sys
import math

lines = sys.stdin.read().splitlines()
seq = "".join([l for l in lines if not l.startswith(">")])
if not seq:
    K = 0.0
else:
    K = (seq.count('G') + seq.count('C')) / len(seq)

x = 100.0
t = 0.0
dt = 0.1
while t < 5.0:
    dx = - K * x * dt
    x += dx
    t += dt
    dt = 0.1 * (1.0 + K)

x_exact = 100.0 * math.exp(-K * 5.0)
print(f"{x:.4f} {x_exact:.4f}")
EOF
    chmod +x /app/oracle_bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
