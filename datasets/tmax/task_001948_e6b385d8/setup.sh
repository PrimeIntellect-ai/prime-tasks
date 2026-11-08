#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat expect
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mock_service.py
#!/usr/bin/env python3
import socket
import sys
import threading

def handle_client(conn, addr):
    try:
        conn.sendall(b"User: ")
        user = conn.recv(1024).decode().strip()
        conn.sendall(b"Pass: ")
        pw = conn.recv(1024).decode().strip()
        if user == "sre_admin" and pw == "KeepAlive42!":
            conn.sendall(b"AUTH_SUCCESS: System Healthy\n")
        else:
            conn.sendall(b"AUTH_FAILED\n")
    except:
        pass
    finally:
        conn.close()

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 8022))
    s.listen(5)
    while True:
        try:
            conn, addr = s.accept()
            t = threading.Thread(target=handle_client, args=(conn, addr))
            t.daemon = True
            t.start()
        except KeyboardInterrupt:
            break

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/service_ctl.sh
#!/bin/bash
PID_FILE="/home/user/service.pid"

start() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "Service already running"
    else
        python3 /home/user/mock_service.py > /dev/null 2>&1 &
        echo $! > "$PID_FILE"
        echo "Service started"
    fi
}

stop() {
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE") 2>/dev/null
        rm -f "$PID_FILE"
        echo "Service stopped"
    fi
}

status() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "Service is running"
    else
        echo "Service is stopped"
    fi
}

case "$1" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    restart) stop; sleep 1; start ;;
    *) echo "Usage: $0 {start|stop|status|restart}" ;;
esac
EOF

    chmod +x /home/user/mock_service.py /home/user/service_ctl.sh

    # Wrapper to ensure service is running when tests are executed
    if [ -f /usr/local/bin/pytest ]; then
        mv /usr/local/bin/pytest /usr/local/bin/pytest.orig
        cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
/home/user/service_ctl.sh start >/dev/null 2>&1
exec /usr/local/bin/pytest.orig "$@"
EOF
        chmod +x /usr/local/bin/pytest
    fi

    echo "/home/user/service_ctl.sh start >/dev/null 2>&1" >> /etc/bash.bashrc

    chmod -R 777 /home/user
