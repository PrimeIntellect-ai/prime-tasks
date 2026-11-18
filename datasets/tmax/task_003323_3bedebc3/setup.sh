#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server netcat cron wget tar
    pip3 install pytest

    # Install Go 1.21
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin

    mkdir -p /app/oracle

    # Create the raw stream server
    cat << 'EOF' > /app/server.py
import socket
import time
import threading

def handle(conn):
    try:
        while True:
            conn.sendall(b"1700000000,S1,10\n")
            time.sleep(0.1)
    except:
        pass
    finally:
        conn.close()

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 8080))
s.listen(5)
while True:
    conn, addr = s.accept()
    t = threading.Thread(target=handle, args=(conn,))
    t.daemon = True
    t.start()
EOF

    # Create dummy legacy cleaner oracle
    cat << 'EOF' > /app/oracle/legacy_cleaner.go
package main
import (
    "bufio"
    "os"
)
func main() {
    scanner := bufio.NewScanner(os.Stdin)
    for scanner.Scan() {
        // dummy implementation
    }
}
EOF
    /usr/local/go/bin/go build -ldflags="-s -w" -o /app/oracle/legacy_cleaner /app/oracle/legacy_cleaner.go

    # Hook to start services on container execution
    cat << 'EOF' > /.singularity.d/env/99-services.sh
if command -v nc >/dev/null 2>&1; then
    if ! nc -z 127.0.0.1 6379 2>/dev/null; then
        redis-server --daemonize yes >/dev/null 2>&1 || true
    fi
    if ! nc -z 127.0.0.1 8080 2>/dev/null; then
        nohup python3 /app/server.py >/dev/null 2>&1 &
    fi
fi
export PATH=$PATH:/usr/local/go/bin
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
