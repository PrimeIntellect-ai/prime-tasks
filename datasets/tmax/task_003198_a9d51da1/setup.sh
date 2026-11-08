#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gnupg gcc binutils
    pip3 install pytest pillow

    mkdir -p /app

    # Generate the screenshot with the hidden passphrase
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((50,100), 'Master Passphrase: Secr3t_R0tation_Key', fill=(0,0,0))
img.save('/app/incident_screenshot.png')
"

    # Create the corpus
    mkdir -p /tmp/corpus/clean /tmp/corpus/evil
    echo "./legacy_deployer --db-pass MySecret123 -v" > /tmp/corpus/evil/1.txt
    echo "./legacy_deployer --auth-token=ABCDEF" > /tmp/corpus/evil/2.txt
    echo "./legacy_deployer -K secret_key" > /tmp/corpus/evil/3.txt
    echo "./legacy_deployer --help" > /tmp/corpus/clean/1.txt
    echo "ls -l /var/log" > /tmp/corpus/clean/2.txt
    echo "./legacy_deployer -K-not-the-key" > /tmp/corpus/clean/3.txt

    cd /tmp
    tar -czf corpus.tar.gz corpus/
    echo "Secr3t_R0tation_Key" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 -o /app/corpus.tar.gz.gpg corpus.tar.gz

    # Create the legacy binary
    cat << 'EOF' > /tmp/legacy_deployer.c
#include <stdio.h>
int main() {
    const char* f1 = "--db-pass";
    const char* f2 = "-K";
    const char* f3 = "--auth-token=";
    return 0;
}
EOF
    gcc /tmp/legacy_deployer.c -o /app/legacy_deployer
    chmod +x /app/legacy_deployer

    # Clean up tmp files
    rm -rf /tmp/corpus /tmp/corpus.tar.gz /tmp/legacy_deployer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
