#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        jq \
        socat \
        netcat-openbsd

    pip3 install pytest Pillow

    mkdir -p /app/clean_bios /app/evil_bios
    useradd -m -s /bin/bash user || true

    # Create server instructions image using Python and Pillow
    cat << 'EOF' > /tmp/make_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "Server Config: Timezone is Pacific/Auckland. The internal backend port is 9090.", fill=(0, 0, 0))
img.save('/app/server_instructions.png')
EOF
    python3 /tmp/make_img.py
    rm /tmp/make_img.py

    # Create sync_users.sh script
    cat << 'EOF' > /home/user/sync_users.sh
#!/bin/bash
jq -n '{}' > /dev/null
echo "Synced" > sync.log
EOF
    chmod +x /home/user/sync_users.sh

    # Create clean bios
    echo "Hello, I am a new user. I like coding!" > /app/clean_bios/1.txt
    echo "Just a normal bio, nothing to see here." > /app/clean_bios/2.txt
    echo "I love 100% pure apple juice." > /app/clean_bios/3.txt

    # Create evil bios
    echo "I am the ADMIN of this site." > /app/evil_bios/1.txt
    echo "Check out my site <script>alert(1)</script>" > /app/evil_bios/2.txt
    echo "My bio | rm -rf /" > /app/evil_bios/3.txt
    echo "Hacker \`whoami\`" > /app/evil_bios/4.txt
    echo "Give me \$MONEY" > /app/evil_bios/5.txt
    echo "admin" > /app/evil_bios/6.txt

    chmod -R 777 /home/user /app
