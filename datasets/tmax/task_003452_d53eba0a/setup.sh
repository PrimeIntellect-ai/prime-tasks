#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/proxy /home/user/backend /home/user/run /home/user/logs

    cat << 'EOF' > /home/user/backend/server.sh
#!/bin/bash
mkdir -p /home/user/run /home/user/logs
rm -f /home/user/run/backend_v2.sock

# Mock backend server listening on unix socket
python3 -c "
import socket, os, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind('/home/user/run/backend_v2.sock')
s.listen(5)
while True:
    try:
        conn, addr = s.accept()
        conn.recv(1024)
        conn.sendall(b'HTTP/1.1 200 OK\r\n\r\nBackend V2')
        conn.close()
    except:
        pass
" &
echo $! > /home/user/run/backend.pid

# Aggressive logger
while true; do
    head -c 10000 /dev/urandom | base64 >> /home/user/logs/backend.log
    sleep 0.5
done
EOF
    chmod +x /home/user/backend/server.sh

    cat << 'EOF' > /home/user/proxy/config.env
UPSTREAM_SOCKET=/home/user/run/backend_v1.sock
EOF

    cat << 'EOF' > /home/user/proxy/health_check.sh
#!/bin/bash
source /home/user/proxy/config.env
if [ ! -S "$UPSTREAM_SOCKET" ]; then
    echo "502 BAD GATEWAY: Socket not found"
    exit 1
fi

RES=$(python3 -c "
import socket
try:
    s=socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2.0)
    s.connect('$UPSTREAM_SOCKET')
    s.send(b'GET / HTTP/1.1\r\n\r\n')
    print(s.recv(1024).decode())
except Exception as e:
    print('Error')
" 2>/dev/null)

if [[ "$RES" == *"200 OK"* ]]; then
    echo "200 OK: Backend Healthy"
    exit 0
else
    echo "502 BAD GATEWAY: No response"
    exit 1
fi
EOF
    chmod +x /home/user/proxy/health_check.sh

    chown -R user:user /home/user/proxy /home/user/backend /home/user/run /home/user/logs
    chmod -R 777 /home/user
