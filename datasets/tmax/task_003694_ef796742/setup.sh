#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd cron iptables
    pip3 install pytest

    # Oracle script creation
    mkdir -p /opt/oracle/
    cat << 'EOF' > /opt/oracle/fw_oracle.sh
#!/bin/bash
IFS=';' read -r SRC DST PORTS PROTO ACTION <<< "$1"

CMD="iptables -A INPUT"

if [ "$SRC" != "any" ]; then
    CMD+=" -s $SRC"
fi

if [ "$DST" != "any" ]; then
    CMD+=" -d $DST"
fi

CMD+=" -p $PROTO"

if [ "$PROTO" != "icmp" ] && [ "$PORTS" != "any" ]; then
    if [[ "$PORTS" == *","* ]]; then
        CMD+=" -m multiport --dports $PORTS"
    else
        CMD+=" --dport $PORTS"
    fi
fi

CMD+=" -j $ACTION"

echo "$CMD"
EOF
    chmod +x /opt/oracle/fw_oracle.sh

    # Vendored package setup
    mkdir -p /app/vendored/echo_server-1.0.0
    cat << 'EOF' > /app/vendored/echo_server-1.0.0/server.py
import socket
import os

socket_path = "/tmp/upstream_sock_wrong_path" # Perturbation

if os.path.exists(socket_path):
    os.remove(socket_path)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(socket_path)
server.listen(1)

while True:
    conn, addr = server.accept()
    data = conn.recv(1024)
    if not data:
        break
    conn.sendall(data)
    conn.close()
EOF
    chmod +x /app/vendored/echo_server-1.0.0/server.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
