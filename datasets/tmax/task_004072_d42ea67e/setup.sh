#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg nginx gcc netcat-openbsd
pip3 install pytest

mkdir -p /app/corpora/clean /app/corpora/evil /app/backend /home/user

# Clean corpus
echo '{"sensor":"temp","value":22.5}' > /app/corpora/clean/t1.json
echo '{"sensor":"humidity","value":45}' > /app/corpora/clean/t2.json

# Evil corpus
echo '{"sensor":"temp","value":"DROP TABLE sensors;"}' > /app/corpora/evil/e1.json
printf '{"sensor":"name","value":"%1001s"}' "A" | tr ' ' 'A' > /app/corpora/evil/e2.json
echo '{"sensor":"broken", "value": 1' > /app/corpora/evil/e3.json

# Telemetry daemon (Python)
cat << 'EOF' > /app/backend/telemetry_daemon
#!/usr/bin/env python3
import socket
import sys

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 8080))
    s.listen(1)
    while True:
        conn, addr = s.accept()
        data = conn.recv(4096)
        if b"DROP TABLE" in data:
            sys.exit(1)
        conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK")
        conn.close()

if __name__ == "__main__":
    main()
EOF
chmod +x /app/backend/telemetry_daemon

# Video fixture
ffmpeg -f lavfi -i "testsrc=duration=11:size=320x240:rate=1" -c:v libx264 -y /tmp/part1.mp4
ffmpeg -f lavfi -i "color=c=black:duration=3:size=320x240:rate=1" -c:v libx264 -y /tmp/part2.mp4
ffmpeg -f lavfi -i "testsrc=duration=10:size=320x240:rate=1" -c:v libx264 -y /tmp/part3.mp4
ffmpeg -f lavfi -i "color=c=black:duration=2:size=320x240:rate=1" -c:v libx264 -y /tmp/part4.mp4
ffmpeg -f lavfi -i "testsrc=duration=4:size=320x240:rate=1" -c:v libx264 -y /tmp/part5.mp4

cat << 'EOF' > /tmp/inputs.txt
file '/tmp/part1.mp4'
file '/tmp/part2.mp4'
file '/tmp/part3.mp4'
file '/tmp/part4.mp4'
file '/tmp/part5.mp4'
EOF

ffmpeg -f concat -safe 0 -i /tmp/inputs.txt -c copy -y /app/incident_record.mp4
rm /tmp/part*.mp4 /tmp/inputs.txt

# Nginx broken config
cat << 'EOF' > /etc/nginx/sites-enabled/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    location /telemetry {
        proxy_pass http://127.0.0.1:8081;
    }
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
