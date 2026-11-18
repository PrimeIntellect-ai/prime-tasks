#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc qemu-system-x86 iproute2 sudo
    pip3 install pytest

    mkdir -p /home/user/app
    mkdir -p /home/user/workspace
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil
    mkdir -p /home/user/hidden_corpus/clean
    mkdir -p /home/user/hidden_corpus/evil

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
python3 /home/user/app/dashboard.py &
# QEMU startup would go here
EOF
    chmod +x /home/user/app/start_services.sh

    cat << 'EOF' > /home/user/app/dashboard.py
import socket
import sys

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('127.0.0.1', 8080))
    s.listen(1)
    with open('/home/user/app/dashboard.log', 'w') as f:
        while True:
            conn, addr = s.accept()
            data = conn.recv(1024)
            if data:
                f.write(data.decode('utf-8', errors='ignore'))
                f.flush()
            conn.close()

if __name__ == '__main__':
    main()
EOF

    echo "Jan 1 12:00:00 host sshd: Accepted publickey for user" > /home/user/corpus/clean/sample1.log
    echo "Jan 1 12:00:00 host sshd: Accepted publickey for user; rm -rf /" > /home/user/corpus/evil/sample1.log

    echo "ALL ALL=(ALL) NOPASSWD: /usr/sbin/ip" >> /etc/sudoers

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
