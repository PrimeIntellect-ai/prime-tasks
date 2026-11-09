#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mock_smtp.py
import socket
import sys

def run_mock_smtp():
    host = '127.0.0.1'
    port = 2525

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((host, port))
    server.listen(1)

    while True:
        conn, addr = server.accept()
        conn.send(b"220 Mock SMTP Server Ready\r\n")

        email_data = ""
        in_data = False

        while True:
            data = conn.recv(1024).decode('utf-8')
            if not data:
                break

            lines = data.split('\r\n')
            for line in lines:
                if not line and not in_data: continue

                if line.upper().startswith("HELO"):
                    conn.send(b"250 Hello\r\n")
                elif line.upper().startswith("MAIL FROM:"):
                    conn.send(b"250 OK\r\n")
                elif line.upper().startswith("RCPT TO:"):
                    conn.send(b"250 OK\r\n")
                elif line.upper() == "DATA":
                    in_data = True
                    conn.send(b"354 End data with <CR><LF>.<CR><LF>\r\n")
                elif line == ".":
                    in_data = False
                    conn.send(b"250 OK: queued as 12345\r\n")
                    with open('/home/user/email_alerts.log', 'a') as f:
                        f.write(email_data + "\n---END---\n")
                    email_data = ""
                elif line.upper() == "QUIT":
                    conn.send(b"221 Bye\r\n")
                    conn.close()
                    break
                elif in_data:
                    email_data += line + "\n"

if __name__ == "__main__":
    run_mock_smtp()
EOF

    chmod -R 777 /home/user
