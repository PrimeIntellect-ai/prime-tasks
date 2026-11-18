#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++ imagemagick fonts-liberation
    pip3 install pytest

    mkdir -p /app

    # Remove ImageMagick policy file to allow label generation
    rm -f /etc/ImageMagick-6/policy.xml

    convert -background white -fill black -font Liberation-Mono -pointsize 18 label:"WS ROUTING SECURITY RULES:\n1. Scheme must be exactly 'ws://' or 'wss://'.\n2. Reject if the string '/admin/' appears anywhere in the URL path.\n3. The query string must contain a 'token' parameter (e.g. ?token=XYZ or &token=XYZ).\n4. The 'token' value must be exactly 16 alphanumeric characters." /app/ws_rules.png

    cat << 'EOF' > /app/clean_urls.txt
wss://api.example.com/chat?token=A1b2C3d4E5f6G7h8
ws://127.0.0.1:8080/stream?room=2&token=1234567890abcdef
wss://test.com/route?user=alice&token=aB3dE5fG7h9J1k2M&region=us
EOF

    cat << 'EOF' > /app/evil_urls.txt
http://api.example.com/chat?token=A1b2C3d4E5f6G7h8
wss://api.example.com/admin/settings?token=A1b2C3d4E5f6G7h8
wss://api.example.com/chat?token=A1b2C3d4E5f
wss://api.example.com/chat?token=A1b2C3d4E5f6G7h899
ws://api.example.com/chat?token=A1b2C3d4E5f6G7h!
wss://api.example.com/chat?room=1
wss://api.example.com/admin/?token=1234567890abcdef
wss://api.example.com/chat?tok=1234567890abcdef
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
