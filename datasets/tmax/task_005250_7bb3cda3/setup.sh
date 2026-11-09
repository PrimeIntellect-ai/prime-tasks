#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required tools for the task and video generation
    apt-get install -y ffmpeg fonts-dejavu-core tesseract-ocr libtesseract-dev rustc cargo

    # Create app directory
    mkdir -p /app

    # Create the master secret key
    echo "super_secret_master_key_1234567890" > /app/master_secret.key
    # Leave permissions default, the agent is expected to change it to 0400

    # Generate the dummy video with the leaked credentials
    # Base64 encoded payloads:
    # {"uid": "admin_992"} -> eyJ1aWQiOiAiYWRtaW5fOTkyIn0=
    # {"uid": "user_103"} -> eyJ1aWQiOiAidXNlcl8xMDMifQ==
    # {"uid": "service_db_44"} -> eyJ1aWQiOiAic2VydmljZV9kYl80NCJ9
    # {"uid": "sys_ops_01"} -> eyJ1aWQiOiAic3lzX29wc18wMSJ9

    cat << 'EOF' > /tmp/leak.txt
HTTP/1.1 200 OK
Authorization: Bearer eyJ1aWQiOiAiYWRtaW5fOTkyIn0=
Accept: application/json

HTTP/1.1 200 OK
Cookie: session=eyJ1aWQiOiAidXNlcl8xMDMifQ==
Accept: application/json

HTTP/1.1 200 OK
Authorization: Bearer eyJ1aWQiOiAic2VydmljZV9kYl80NCJ9
Accept: application/json

HTTP/1.1 200 OK
Cookie: session=eyJ1aWQiOiAic3lzX29wc18wMSJ9
Accept: application/json
EOF

    ffmpeg -f lavfi -i color=c=black:s=800x600:d=2 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:textfile=/tmp/leak.txt:fontcolor=white:fontsize=24:x=50:y=50" -c:v libx264 /app/leak_capture.mp4
    rm /tmp/leak.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
