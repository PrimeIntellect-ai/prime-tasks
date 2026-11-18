#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the image with the hidden target domain
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (600, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = 'OPERATION DARKSTAR\nTarget Domain: malicious-redirect-host.local\nExfil port: 443'
d.text((10,10), text, fill=(0,0,0))
img.save('/app/exfil_target.png')
"

    # Populate clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.txt
Just a normal file with a link to https://example.com/login
This is totally safe.
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.txt
Here is my public key:
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3... user@host
EOF

    # Populate evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1.txt
Check out this link: https://example.com/login?next=http://malicious-redirect-host.local/steal
It is definitely not safe.
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.txt
My private key is:
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACD...
-----END OPENSSH PRIVATE KEY-----
Don't share it!
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
