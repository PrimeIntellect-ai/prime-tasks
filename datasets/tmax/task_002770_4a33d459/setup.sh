#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg curl jq
pip3 install pytest SpeechRecognition

mkdir -p /app
espeak -w /app/incident_comms.wav "Focus the extraction on target IP 192.168.55.104"

cat << 'EOF' > /app/raw_traffic_logs.txt
[2023-10-04T08:15:32Z] Connection from IP: 192.168.55.104 - payload size: 5000 bytes
[2023-10-04T08:45:10Z] Connection from IP: 192.168.55.104 - payload size: 2500 bytes
EOF

# Add a line with cp1252 special characters to test encoding handling
echo -e "[2023-10-04T09:05:00Z] Connection from IP: 10.0.0.1 - payload size: 100 bytes \x93special\x94" >> /app/raw_traffic_logs.txt
echo "[2023-10-04T09:20:11Z] Connection from IP: 192.168.55.104 - payload size: 8000 bytes" >> /app/raw_traffic_logs.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
