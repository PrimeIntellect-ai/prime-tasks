#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc make libssl-dev sqlite3
    pip3 install pytest qrcode Pillow

    # Setup script execution context
    mkdir -p /app

    # Generate video artifact
    cat << 'EOF' > /tmp/gen_video.py
import qrcode
from PIL import Image
import subprocess
import os

token = 'CI_TOKEN_8847A29F'
qr = qrcode.make(token).convert('RGB')
qr = qr.resize((200, 200))

os.makedirs('/tmp/frames', exist_ok=True)
for i in range(50):
    img = Image.new('RGB', (640, 480), color=(255, 255, 255))
    if i == 30:
        img.paste(qr, (220, 140))
    img.save(f'/tmp/frames/frame_{i:03d}.png')

subprocess.run(['ffmpeg', '-y', '-framerate', '10', '-i', '/tmp/frames/frame_%03d.png', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '/app/ci_test_run.mp4'])
EOF
    python3 /tmp/gen_video.py

    # C Library Files Setup
    mkdir -p /home/user/auth-lib
    cat << 'EOF' > /home/user/auth-lib/auth.c
#include <math.h>
#include <openssl/sha.h>
#include <stddef.h>

int compute_auth_hash() {
    double v = pow(2.0, 3.0);
    return (int)v;
}
EOF

    cat << 'EOF' > /home/user/auth-lib/Makefile
# Broken Makefile - missing libraries and bad syntax
libauth.so: auth.c
	gcc -shared -fPIC -o libauth.so auth.c 
	# MISSING: -lm -lcrypto
EOF

    cat << 'EOF' > /home/user/auth-lib/test_load.py
import ctypes
lib = ctypes.CDLL('./libauth.so')
assert lib.compute_auth_hash() == 8
print("Success")
EOF

    # Database Setup
    mkdir -p /home/user/db
    sqlite3 /home/user/db/audit.db "CREATE TABLE log_entries (id INTEGER PRIMARY KEY, action TEXT, timestamp INTEGER);"
    sqlite3 /home/user/db/audit.db "INSERT INTO log_entries (action, timestamp) VALUES ('login_attempt', 1625097600);"
    sqlite3 /home/user/db/audit.db "INSERT INTO log_entries (action, timestamp) VALUES ('password_change', 1625097660);"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
