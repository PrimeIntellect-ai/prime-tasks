#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx ffmpeg socat curl gawk
    pip3 install pytest

    # Create directories
    mkdir -p /home/user
    mkdir -p /app

    # Create nginx.conf
    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
daemon off;
error_log /dev/null;
events { worker_connections 1024; }
http {
    access_log off;
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:8000; # Incorrect port initially
            proxy_connect_timeout 1s;
        }
    }
}
EOF

    # Create backend.sh
    cat << 'EOF' > /home/user/backend.sh
#!/bin/bash
USER_EXPECTED="svc_backend"
PORT_EXPECTED="9090"

if [ "$(whoami)" != "$USER_EXPECTED" ]; then
    echo "Error: Must run as $USER_EXPECTED" >&2
    exit 1
fi

PORT=${1:-9090}
if [ "$PORT" != "$PORT_EXPECTED" ]; then
    echo "Error: Must run on port $PORT_EXPECTED" >&2
    exit 1
fi

# Simulate an HTTP server that crashes after handling 3 requests
tmp_pipe="/tmp/pipe_$$"
rm -f "$tmp_pipe"
mkfifo "$tmp_pipe"
trap "rm -f $tmp_pipe" EXIT

count=0
while [ $count -lt 3 ]; do
    read line <$tmp_pipe
    if [[ "$line" == GET* ]]; then
        echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK" | socat -t 1 - UNIX-CONNECT:/tmp/nonexistent 2>/dev/null || echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
        count=$((count+1))
    fi
done | socat TCP-LISTEN:$PORT,reuseaddr,fork PIPE:$tmp_pipe >/dev/null 2>&1
exit 0
EOF

    chmod +x /home/user/backend.sh

    # Create video file
    ffmpeg -f lavfi -i "color=c=black:s=640x480:d=5" -vf "drawtext=text='FATAL\: Backend must run as user svc_backend':fontcolor=white:fontsize=24:x=10:y=10, drawtext=text='FATAL\: Configuration mismatch. Required internal port is 9090':fontcolor=white:fontsize=24:x=10:y=50" -c:v libx264 -y /app/incident_log.mp4

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
