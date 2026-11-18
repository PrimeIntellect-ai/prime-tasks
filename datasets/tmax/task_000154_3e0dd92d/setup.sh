#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx ffmpeg gcc netcat-openbsd systemd

pip3 install pytest

mkdir -p /app
# Generate video quickly with ultrafast preset and 1 fps
ffmpeg -y -f lavfi -i color=c=black:s=320x240:r=1 -t 60 \
  -vf "drawbox=x=0:y=0:w=16:h=16:color=red@1:t=fill:enable='between(t,12,15)+between(t,42,47)'" \
  -c:v libx264 -preset ultrafast /app/dashboard_recording.mp4

# Configure Nginx
cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    location / {
        proxy_pass http://unix:/run/api-backend/api.sock;
    }
}
EOF

# Create dummy backend service
cat << 'EOF' > /etc/systemd/system/api-backend.service
[Unit]
Description=API Backend

[Service]
Type=simple
ExecStart=/bin/sh -c 'rm -f /run/api-backend/api.sock && nc -l -U /run/api-backend/api.sock'
UMask=0022
Restart=always

[Install]
WantedBy=multi-user.target
EOF
mkdir -p /run/api-backend

# Populate corpora
mkdir -p /app/corpora/clean /app/corpora/evil

cat << 'EOF' > /app/corpora/clean/req1.txt
GET / HTTP/1.1
Host: localhost
X-Trace-Id: 12345678-1234-1234-1234-123456789012

EOF

cat << 'EOF' > /app/corpora/clean/req2.txt
POST /api HTTP/1.1
Host: localhost
X-Trace-Id: abcdef

EOF

cat << 'EOF' > /app/corpora/evil/req1.txt
GET / HTTP/1.1
Host: localhost
X-Trace-Id: $(reboot)

EOF

cat << 'EOF' > /app/corpora/evil/req2.txt
GET / HTTP/1.1
Host: localhost
X-Trace-Id: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
