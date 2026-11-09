#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-liberation
    pip3 install pytest

    mkdir -p /app
    convert -size 400x100 xc:white -fill black -pointsize 24 -annotate +10+50 'TargetEncoding: utf-16le' /app/evidence.png

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/ip_map.csv
ip_address,department
192.168.1.10,Engineering
192.168.1.50,HR
10.0.0.5,Finance
EOF

    python3 -c "
logs = [
    '2024-01-01T10:00:00Z|192.168.1.10|Intrusion attempt ErrCode:9021',
    '2024-01-01T10:00:00Z|192.168.1.10|Intrusion attempt ErrCode:9021',
    '2024-01-01T10:05:00Z|10.0.0.5|Malformed packet ErrCode:404',
    '2024-01-01T10:10:00Z|192.168.1.10|Data exfiltration ErrCode:9999'
]
with open('/home/user/raw_logs.dat', 'wb') as f:
    f.write('\n'.join(logs).encode('utf-16le'))
"

    chmod -R 777 /home/user /app
