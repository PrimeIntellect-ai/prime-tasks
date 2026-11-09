#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg openssl gcc zip unzip
pip3 install pytest pillow

mkdir -p /app/training_data/evil /app/training_data/clean
mkdir -p /app/hidden_eval/evil /app/hidden_eval/clean

# Create training data
cat << 'EOF' > /app/training_data/evil/1.txt
e\v\a\l "echo bad"
EOF
cat << 'EOF' > /app/training_data/evil/2.txt
n'c' -e /bin/bash
EOF
cat << 'EOF' > /app/training_data/evil/3.txt
e"v"a'l'
EOF
cat << 'EOF' > /app/training_data/clean/1.txt
echo "hello world"
EOF
cat << 'EOF' > /app/training_data/clean/2.txt
netstat -an
EOF
cat << 'EOF' > /app/training_data/clean/3.txt
cat /etc/passwd
EOF

# Create hidden eval data
cat << 'EOF' > /app/hidden_eval/evil/1.txt
e\v'a'l
EOF
cat << 'EOF' > /app/hidden_eval/evil/2.txt
n"c"
EOF
cat << 'EOF' > /app/hidden_eval/evil/3.txt
\n\c
EOF
cat << 'EOF' > /app/hidden_eval/evil/4.txt
'e'v"a"l
EOF
cat << 'EOF' > /app/hidden_eval/clean/1.txt
echo "safe"
EOF
cat << 'EOF' > /app/hidden_eval/clean/2.txt
ls -la
EOF
cat << 'EOF' > /app/hidden_eval/clean/3.txt
grep "foo" bar.txt
EOF

# Zip and encrypt training data
cd /app
zip -r training_data.zip training_data
openssl enc -aes-256-cbc -pbkdf2 -in training_data.zip -out training_data.zip.enc -pass pass:SYS
rm -rf training_data training_data.zip

# Generate frames and video
cat << 'EOF' > /tmp/gen_frames.py
from PIL import Image
import os

bits = [0, 1, 0, 1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1]
os.makedirs('/tmp/frames', exist_ok=True)

for i, bit in enumerate(bits):
    img = Image.new('RGB', (100, 100), color='black')
    if bit == 1:
        for x in range(20):
            for y in range(20):
                img.putpixel((x, y), (255, 255, 255))
    img.save(f'/tmp/frames/frame_{i:03d}.png')
EOF

python3 /tmp/gen_frames.py
ffmpeg -framerate 1 -i /tmp/frames/frame_%03d.png -c:v libx264 -r 1 -pix_fmt yuv420p /app/surveillance.mp4
rm -rf /tmp/frames /tmp/gen_frames.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
