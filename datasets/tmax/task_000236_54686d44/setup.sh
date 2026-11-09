#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick qrencode ffmpeg gcc zip openssl
    pip3 install pytest

    mkdir -p /app/frames
    mkdir -p /home/user/vault_staging

    # 1. Video Fixture
    for i in 1 2 3 4 5; do
        convert -size 640x480 xc:black /app/frames/frame_$i.png
    done
    qrencode -o /app/qr.png "compromised_master_key_992!"
    composite -geometry +200+100 /app/qr.png /app/frames/frame_3.png /app/frames/frame_3.png
    ffmpeg -framerate 1 -i /app/frames/frame_%d.png -c:v libx264 -pix_fmt yuv420p /app/incident_screen_record.mp4

    # 2. Vault Creation
    cat << 'EOF' > /home/user/vault_staging/payload.c
const char signature[] __attribute__((section(".rodata"))) = "\xDE\xAD\xBE\xEF\x11\x22\x33\x44\x55\x66\x77\x88";
int main() { return 0; }
EOF
    gcc -o /home/user/vault_staging/payload.elf /home/user/vault_staging/payload.c
    cd /home/user/vault_staging && zip -r ../vault.zip *
    openssl enc -aes-256-cbc -pbkdf2 -salt -in /home/user/vault.zip -out /home/user/vault.enc -pass pass:compromised_master_key_992!
    rm -rf /home/user/vault_staging /home/user/vault.zip

    # 3. Test Log File Generation (Fast Python script)
    cat << 'EOF' > /app/generate_logs.py
import random

hex_chars = "0123456789abcdef"
signature = "deadbeef1122334455667788"

# Generate 500,000 lines quickly
pool = ["".join(random.choices(hex_chars, k=64)) + "\n" for _ in range(10000)]
lines = []
for _ in range(50):
    lines.extend(pool)

indices = random.sample(range(500000), 42)
for idx in indices:
    line = lines[idx]
    pos = random.randint(0, 64 - len(signature))
    lines[idx] = line[:pos] + signature + line[pos+len(signature):]

with open("/app/test_logs.txt", "w") as f:
    f.writelines(lines)
EOF
    python3 /app/generate_logs.py
    rm /app/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
