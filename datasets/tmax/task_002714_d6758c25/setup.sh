#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Generate the image with the parameters
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -annotate +10+40 "Gene Circuit Parameters:\nalpha=2.5\nbeta=0.2\nn=2" /app/model_params.png

    # Create the oracle script
    cat << 'EOF' > /app/oracle_simulate.py
#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) < 2:
        print("0.0000")
        return
    seq = sys.argv[1].upper()
    if len(seq) == 0:
        print("0.0000")
        return

    gc_count = seq.count('G') + seq.count('C')
    x = gc_count / len(seq)

    alpha = 2.5
    beta = 0.2
    n = 2
    dt = 0.1

    for _ in range(100):
        dx = alpha * (1.0 / (1.0 + x**n)) - beta * x
        x = x + dt * dx

    print(f"{x:.4f}")

if __name__ == '__main__':
    main()
EOF

    chmod +x /app/oracle_simulate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
