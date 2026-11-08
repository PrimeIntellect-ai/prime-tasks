#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user/incident/bin
    mkdir -p /home/user/incident/certs

    cat << 'EOF' > /home/user/incident/web.log
192.168.1.50 - - [10/Oct/2023:13:55:36 +0000] "GET / HTTP/1.1" 404 - "X-Malware-Drop: aWdub3JlX21l"
192.168.1.100 - - [10/Oct/2023:14:02:11 +0000] "POST /api/upload HTTP/1.1" 403 - "X-Malware-Drop: ZmFrZV9wYXlsb2Fk"
192.168.1.100 - - [10/Oct/2023:14:05:00 +0000] "POST /api/v1/endpoint HTTP/1.1" 200 - "X-Malware-Drop: dGFyZ2V0X2Jpbj1zeXN0ZW1fYmFja3Vw"
10.0.0.5 - - [10/Oct/2023:14:10:00 +0000] "GET / HTTP/1.1" 200 - "X-Malware-Drop: bm90aGluZw=="
EOF

    touch /home/user/incident/bin/system_backup
    touch /home/user/incident/bin/cleaner
    touch /home/user/incident/bin/logger

    cd /home/user/incident/certs
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout rootCA.key -out rootCA.pem -subj "/C=US/ST=State/L=City/O=Org/OU=IT/CN=FakeRootCA"
    openssl req -newkey rsa:2048 -nodes -keyout implant.key -out implant.csr -subj "/C=US/ST=State/L=City/O=Org/OU=Compromised/CN=malicious-node.local"
    openssl x509 -req -in implant.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out implant.pem -days 365
    cd /

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

    # Set SUID bit after chmod -R 777 so it is not overwritten
    chmod 4755 /home/user/incident/bin/system_backup
