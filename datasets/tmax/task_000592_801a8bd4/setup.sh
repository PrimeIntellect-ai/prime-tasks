#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat netcat-openbsd
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/ingress.py
#!/usr/bin/env python3
import socket
import threading

def handle_client(conn):
    data = conn.recv(65535)
    conn.close()
    if data:
        try:
            s = socket.socket()
            s.connect(('127.0.0.1', 10026))
            s.sendall(data)
            s.close()
        except:
            pass

s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 10025))
s.listen(5)
while True:
    conn, addr = s.accept()
    threading.Thread(target=handle_client, args=(conn,), daemon=True).start()
EOF

    cat << 'EOF' > /app/egress.py
#!/usr/bin/env python3
import socket
import threading

def handle_client(conn):
    data = b""
    while True:
        chunk = conn.recv(4096)
        if not chunk:
            break
        data += chunk
    conn.close()
    if data:
        with open('/app/egress_out.log', 'ab') as f:
            f.write(data + b"\n---END---\n")

s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 10027))
s.listen(5)
while True:
    conn, addr = s.accept()
    threading.Thread(target=handle_client, args=(conn,), daemon=True).start()
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nohup python3 /app/ingress.py > /dev/null 2>&1 &
nohup python3 /app/egress.py > /dev/null 2>&1 &
EOF

    cat << 'EOF' > /app/oracle_sanitize
#!/usr/bin/env python3
import sys

def sanitize(text):
    text = text.replace('\r\n', '\n')
    lines = text.split('\n')
    out_lines = []
    for line in lines:
        if line.startswith('X-Internal-Trace-ID: '):
            continue
        out_lines.append(line)

    subject_idx = -1
    for i, line in enumerate(out_lines):
        if line.startswith('Subject: '):
            subject_idx = i
            break

    if subject_idx != -1:
        out_lines.insert(subject_idx + 1, 'X-Processed-By: SecRelay-v1')
    else:
        out_lines.insert(0, 'X-Processed-By: SecRelay-v1')

    out_text = '\n'.join(out_lines)
    out_text = out_text.replace('http://insecure.local/', 'https://secure.local/')
    return out_text

if __name__ == '__main__':
    input_data = sys.stdin.read()
    sys.stdout.write(sanitize(input_data))
EOF

    chmod +x /app/start_services.sh /app/oracle_sanitize /app/ingress.py /app/egress.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
