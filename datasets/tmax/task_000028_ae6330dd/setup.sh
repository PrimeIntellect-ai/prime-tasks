#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr python3-opencv
    pip3 install pytest scapy lief pytesseract Pillow

    mkdir -p /app/incident_data
    touch /app/incident_data/capture_session.mp4
    touch /app/incident_data/traffic.pcap
    touch /app/incident_data/auth_logger.elf
    touch /app/incident_data/server_cert.pem
    touch /app/incident_data/suspicious_cert.pem

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/ground_truth.json
[
  {
    "timestamp": "00:01:15",
    "unredacted_payload": "http://evil.com/auth",
    "used_rogue_cert": true
  },
  {
    "timestamp": "00:02:30",
    "unredacted_payload": "http://evil.com/auth",
    "used_rogue_cert": false
  },
  {
    "timestamp": "00:04:45",
    "unredacted_payload": "http://evil.com/auth",
    "used_rogue_cert": true
  }
]
EOF

    chmod -R 777 /home/user
