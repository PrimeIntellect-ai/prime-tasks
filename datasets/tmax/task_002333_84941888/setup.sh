#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /home/user/certs
    mkdir -p /app

    cat << 'EOF' > /home/user/audit_logs.txt
[2023-10-12 10:00:01] LOGIN SUCCESS: admin_charlie from 192.168.1.50
[2023-10-12 10:05:22] PERMISSION GRANTED: admin_charlie read access to /etc/shadow
[2023-10-12 10:15:00] LOGIN SUCCESS: user_alice from 192.168.1.51
[2023-10-12 10:16:33] FILE EXPORT: admin_charlie exported user_database.csv
EOF

    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
    -draw "text 20,40 'SECURITY AUDIT PARAMETERS'" \
    -draw "text 20,80 'REDACT_USER: admin_charlie'" \
    -draw "text 20,120 'AUTH_TOKEN: SecT0k3n_99xA'" \
    /app/auditor_instructions.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
