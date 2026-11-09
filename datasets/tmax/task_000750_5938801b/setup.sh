#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest Pillow pytesseract

mkdir -p /app

# Create the image using Python and Pillow
cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 100), color='white')
d = ImageDraw.Draw(img)
text = "Baseline Model: Poisson distribution with lambda = 4.2"
d.text((10, 40), text, fill='black')
img.save('/app/baseline_model.png')
EOF
python3 /tmp/make_image.py

# Create the oracle script
cat << 'EOF' > /app/oracle_kl
#!/usr/bin/env python3
import sys, math

def main():
    lam = 4.2
    raw_p = [float(x) for x in sys.argv[1].split(',')]
    N = len(raw_p)
    p_clamped = [max(x, 1e-9) for x in raw_p]
    sum_p = sum(p_clamped)
    P = [x / sum_p for x in p_clamped]

    q_raw = []
    for k in range(N):
        val = (lam**k * math.exp(-lam)) / math.factorial(k)
        q_raw.append(max(val, 1e-9))
    sum_q = sum(q_raw)
    Q = [x / sum_q for x in q_raw]

    kl = sum(p * math.log(p / q) for p, q in zip(P, Q))
    print(f"{kl:.6f}")

if __name__ == '__main__':
    main()
EOF
chmod +x /app/oracle_kl

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
