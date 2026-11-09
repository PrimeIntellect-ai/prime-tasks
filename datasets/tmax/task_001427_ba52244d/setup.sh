#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages: tesseract, imagemagick, rust toolchain, fonts
    apt-get install -y tesseract-ocr imagemagick cargo rustc fonts-dejavu-core

    # Create directories
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the image fixture
    # Temporarily modify ImageMagick policy if needed to allow text drawing, though usually fine on 22.04
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'PROJECT CODENAME SECURE' text 10,100 'PREFIX: OMEGA_99' text 10,150 'DO NOT SHARE'" /app/project_spec.png

    # Generate .pza files using a Python script
    cat << 'EOF' > /tmp/gen_pza.py
import struct
import os

def write_pza(filename, files):
    with open(filename, 'wb') as f:
        f.write(b'PZA\x01')
        f.write(struct.pack('<I', len(files)))
        for path, data in files:
            path_bytes = path.encode('utf-8')
            f.write(struct.pack('<H', len(path_bytes)))
            f.write(path_bytes)
            f.write(struct.pack('<I', len(data)))
            f.write(data)

write_pza('/app/corpus/clean/clean1.pza', [('src/main.rs', b'fn main() { println!("Hello"); }')])
write_pza('/app/corpus/clean/clean2.pza', [('docs/readme.txt', b'Documentation')])

write_pza('/app/corpus/evil/evil1.pza', [('../../../etc/passwd', b'root:x:0:0:root:/root:/bin/bash')])
write_pza('/app/corpus/evil/evil2.pza', [('/var/log/syslog', b'malicious log entry')])
EOF

    python3 /tmp/gen_pza.py
    rm /tmp/gen_pza.py

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
