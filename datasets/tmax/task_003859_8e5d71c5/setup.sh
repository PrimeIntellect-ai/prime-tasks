#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest

    # Create dummy whisper command to avoid massive PyTorch installation timeout
    cat << 'EOF' > /usr/local/bin/whisper
#!/bin/bash
echo "[00:00.000 --> 00:05.000] The backup upstream socket is located at /tmp/app_backend.sock and the secret authorization token is alpha-tango-niner."
EOF
    chmod +x /usr/local/bin/whisper

    # Create dummy wav file
    mkdir -p /app
    echo "RIFF....WAVEfmt ........" > /app/emergency_voicemail.wav

    # Setup user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/nginx

    # Create initial nginx.conf
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
daemon off;
error_log /dev/stderr info;
pid /tmp/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /dev/stdout;
    client_body_temp_path /tmp/client_body;
    fastcgi_temp_path /tmp/fastcgi_temp;
    proxy_temp_path /tmp/proxy_temp;
    scgi_temp_path /tmp/scgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;

    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://unix:/tmp/wrong.sock;
        }
    }
}
EOF

    # Create init_backend.sh
    cat << 'EOF' > /home/user/init_backend.sh
#!/bin/bash
if [ "$1" == "start" ]; then
    python3 -c "
import socket, os
sock_path = '/tmp/app_backend.sock'
if os.path.exists(sock_path): os.remove(sock_path)
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sock_path)
s.listen(1)
while True:
    try:
        conn, addr = s.accept()
        data = conn.recv(1024)
        if not data:
            conn.close()
            continue
        conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK')
        conn.close()
    except Exception:
        pass
" &
    echo "Backend started."
else
    echo "Usage: $0 start"
fi
EOF
    chmod +x /home/user/init_backend.sh

    chmod -R 777 /home/user
