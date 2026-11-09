#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core

    pip3 install --default-timeout=100 pytest pytesseract pillow

    # Create app dir and manifest image
    mkdir -p /app
    cat << 'EOF' > /app/text.txt
{
  "files": ["bin_A.dat", "bin_B.dat", "bin_C.dat"],
  "dictionary": {
    "00000000": "01",
    "FFFFFFFF": "02",
    "DEADBEEF": "03"
  }
}
EOF
    # ImageMagick policy fix for PDF/text if needed, but standard text annotation should work
    convert -size 600x400 xc:white -font DejaVu-Sans -pointsize 24 -fill black -annotate +20+40 "$(cat /app/text.txt)" /app/manifest_scan.png

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/repo

    # Create python script to generate binary files and CSV
    cat << 'EOF' > /tmp/setup_files.py
import os

repo = '/home/user/repo'
os.makedirs(repo, exist_ok=True)

# snapshot.csv
with open(os.path.join(repo, 'snapshot.csv'), 'w') as f:
    f.write("filename,last_modified\nbin_A.dat,1700000000\nbin_B.dat,1700000000\nbin_C.dat,1700000000\n")

# bin_A.dat (older)
path_A = os.path.join(repo, 'bin_A.dat')
with open(path_A, 'wb') as f:
    f.write(os.urandom(2048))
os.utime(path_A, (1600000000, 1600000000))

# bin_B.dat (newer)
path_B = os.path.join(repo, 'bin_B.dat')
with open(path_B, 'wb') as f:
    f.write(b'\x00\x00\x00\x00' * 1000 + b'\xde\xad\xbe\xef' * 1000)
os.utime(path_B, (1700000005, 1700000005))

# bin_C.dat (newer)
path_C = os.path.join(repo, 'bin_C.dat')
with open(path_C, 'wb') as f:
    f.write(b'\xff\xff\xff\xff' * 2000)
os.utime(path_C, (1700000010, 1700000010))
EOF

    python3 /tmp/setup_files.py

    chmod -R 777 /home/user
    chmod -R 777 /app
