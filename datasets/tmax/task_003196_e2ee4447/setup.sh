#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        tesseract-ocr \
        jq \
        sqlite3 \
        socat \
        netcat-openbsd \
        curl \
        imagemagick \
        gawk \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app

    # Create the incident memo image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black -annotate +20+40 "CONFIDENTIAL MEMO\n\nPlease investigate recent anomalies.\nAUDIT_ROOT: SRV-091\n\nSign, Management" /app/incident_memo.png

    # Create network traffic CSV
    cat << 'EOF' > /app/network_traffic.csv
src_node,dst_node,protocol,bytes_transferred
SRV-091,PROXY-12,HTTPS,500
SRV-091,PROXY-15,HTTPS,800
SRV-091,PROXY-12,SSH,200
PROXY-12,EXT-88,SCP,1000
PROXY-12,EXT-88,SCP,500
PROXY-15,EXT-99,SCP,3000
PROXY-15,EXT-88,SCP,200
PROXY-12,EXT-77,HTTPS,1500
SRV-092,PROXY-12,HTTPS,999
EOF

    # Create node metadata JSON
    cat << 'EOF' > /app/node_metadata.json
[
  {"node": "EXT-88", "department": "Offshore-Contractors", "owner_id": "U11"},
  {"node": "EXT-99", "department": "Vendor-Cloud", "owner_id": "U22"},
  {"node": "EXT-77", "department": "Internal-Testing", "owner_id": "U33"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
