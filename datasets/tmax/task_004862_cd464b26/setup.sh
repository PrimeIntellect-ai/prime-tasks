#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-liberation
    pip3 install pytest pytesseract Pillow

    mkdir -p /app
    convert -background white -fill black -font Courier -pointsize 24 label:'BAYES_PRIOR=0.35' /app/priors.png

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/processor_oracle.py
#!/usr/bin/env python3
import sys
import math

PRIOR = 0.35

def main():
    lines = sys.stdin.read().strip().split('\n')
    if not lines or lines == ['']:
        return

    token_counts = []
    xs = []
    ys = []

    for line in lines:
        parts = line.split(',', 2)
        if len(parts) < 3: continue
        text, x_str, y_str = parts

        tokens = text.split()
        token_counts.append(len(tokens))
        xs.append(float(x_str))
        ys.append(float(y_str))

        print(f"{len(tokens)},{float(x_str):.4f},{float(y_str):.4f}")

    print("")

    n = len(xs)
    mean_x = sum(xs) / n
    mean_y = sum(ys) / n

    cov = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / n

    prod_x = 1.0
    prod_y = 1.0
    for x in xs: prod_x *= x
    for y in ys: prod_y *= y

    numerator = PRIOR * prod_x
    denominator = numerator + (1.0 - PRIOR) * prod_y

    posterior = 0.0
    if denominator > 0:
        posterior = numerator / denominator

    print(f"COVARIANCE: {cov:.4f}")
    print(f"POSTERIOR: {posterior:.4f}")

if __name__ == '__main__':
    main()
EOF
    chmod +x /opt/oracle/processor_oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
