#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence
    cat << 'EOF' > /home/user/evidence/service.py
import socket
import base64

def get_p():
    enc = [26, 5, 43, 37, 85, 49, 48, 5, 29, 49, 41, 66, 21, 85, 45, 44, 37, 48, 48, 45, 48, 29, 39, 43, 37, 48, 56, 11, 43, 119, 34, 44, 37, 34, 41, 11, 45, 62, 26, 29, 29]
    s = "".join([chr(c ^ 0x42) for c in enc])
    return base64.b64decode(s).decode('utf-8')

def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(('0.0.0.0', 44444))
    sock.listen(5)
    while True:
        client, addr = sock.accept()
        data = client.recv(1024)
        if data:
            with open("access.log", "a") as f:
                f.write(data.decode('utf-8') + get_p() + "\n")
        client.close()

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
