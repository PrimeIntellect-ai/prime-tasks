#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-dejavu-core
    pip3 install pytest pillow

    mkdir -p /app/scripts

    # Create auth.log
    cat << 'EOF' > /app/auth.log
Sep 10 10:00:01 server sshd[123]: Accepted publickey for alice
Sep 10 10:05:22 server sudo: mallory : command not allowed ; TTY=pts/0 ; PWD=/home/mallory ; USER=root ; COMMAND=/bin/bash
Sep 10 10:06:00 server sshd[124]: Accepted publickey for mallory
Sep 10 10:10:00 server sudo: bob : command not allowed ; TTY=pts/1 ; PWD=/home/bob ; USER=root ; COMMAND=/bin/cat /etc/shadow
EOF

    # Create scripts
    echo "echo 'deploying'" > /app/scripts/deploy.sh
    echo "echo 'backdoor'" > /app/scripts/backdoor.sh

    # Create manifest.sha256
    DEPLOY_HASH=$(sha256sum /app/scripts/deploy.sh | awk '{print $1}')
    cat << EOF > /app/manifest.sha256
${DEPLOY_HASH}  deploy.sh
0000000000000000000000000000000000000000000000000000000000000000  backdoor.sh
EOF

    # Generate auth_badge.png with OCR-readable text
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 150), color='white')
d = ImageDraw.Draw(img)
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 50)
d.text((20, 40), 'AUTH-9942X', fill='black', font=font)
img.save('/app/auth_badge.png')
"

    # Set permissions
    chmod -R 777 /app

    # Create user and set home directory permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
