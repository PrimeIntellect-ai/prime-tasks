#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg zbar-tools golang openssl gcc binutils
pip3 install pytest qrcode pillow

mkdir -p /app
cd /app

# Generate RSA key and cert
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/CN=test"

# Python script to generate frames and exfil data
cat << 'EOF' > gen.py
import qrcode
from PIL import Image
import os
import random
import string

# Generate frames for video
with open('key.pem', 'r') as f:
    key_data = f.read()

chunk_size = (len(key_data) + 4) // 5
chunks = [key_data[i:i+chunk_size] for i in range(0, len(key_data), chunk_size)]

os.makedirs('frames', exist_ok=True)
for i in range(1, 11):
    filename = f"frames/frame_{i:02d}.png"
    if i % 2 == 0:
        idx = (i // 2) - 1
        if idx < len(chunks):
            img = qrcode.make(chunks[idx])
            img = img.convert('RGB').resize((400, 400))
            img.save(filename)
        else:
            img = Image.new('RGB', (400, 400), color='white')
            img.save(filename)
    else:
        img = Image.new('RGB', (400, 400), color='white')
        img.save(filename)

# Generate exfil_data
def gen_cc():
    return "-".join(["".join(random.choices(string.digits, k=4)) for _ in range(4)])

def gen_email():
    return "".join(random.choices(string.ascii_lowercase, k=8)) + "@example.com"

def gen_log():
    return "INFO: System running smoothly at " + "".join(random.choices(string.digits, k=10))

def gen_url():
    return "http://malicious.c2/" + "".join(random.choices(string.ascii_lowercase, k=8))

data = []
for _ in range(50): data.append(gen_cc())
for _ in range(50): data.append(gen_email())
for _ in range(100): data.append(gen_log())
for _ in range(50): data.append(gen_url())
random.shuffle(data)

with open("exfil_data.bin", "w") as f:
    f.write("\n".join(data) + "\n")
EOF

python3 gen.py

# Create video
ffmpeg -framerate 1 -i frames/frame_%02d.png -c:v libx264 -r 1 -pix_fmt yuv420p evidence.mp4

# Create dummy ELF
cat << 'EOF' > dummy.c
int main() { return 0; }
EOF
gcc dummy.c -o malware.elf

# Add custom sections to ELF
objcopy --add-section .tls_cert=cert.pem --set-section-flags .tls_cert=alloc,readonly \
        --add-section .exfil_data=exfil_data.bin --set-section-flags .exfil_data=alloc,readonly \
        malware.elf

# Cleanup
rm -rf frames key.pem cert.pem gen.py dummy.c exfil_data.bin

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
