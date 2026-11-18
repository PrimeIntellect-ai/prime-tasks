#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/certs

    # Create access.log
    cat << 'EOF' > /home/user/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /login?next=/dashboard HTTP/1.1" 200 2326 "session_id=a94a8fe5ccb19ba61c4c0873d391e987" "Mozilla/5.0"
10.0.0.5 - - [10/Oct/2023:13:56:01 -0700] "GET /admin HTTP/1.1" 403 512 "session_id=deadbeef12345678" "curl/7.68.0"
192.168.1.12 - - [10/Oct/2023:13:58:11 -0700] "POST /login HTTP/1.1" 302 - "session_id=550e8400e29b41d4a716446655440000" "Mozilla/5.0"
EOF

    # Create vulnerable check_status.sh
    cat << 'EOF' > /home/user/check_status.sh
#!/bin/bash
# Network status checker
LOGFILE="/var/log/network.log"

echo "Checking network status..."

TARGET_IP=$1
if [ -z "$TARGET_IP" ]; then
    echo "Usage: $0 <ip>"
    exit 1
fi

# Ping the target (Vulnerable line below due to lack of sanitization and eval)
eval "ping -c 1 $TARGET_IP" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "$TARGET_IP is UP"
else
    echo "$TARGET_IP is DOWN"
fi
EOF

    # Generate Certificates
    cd /home/user/certs

    # 1. Root CA
    openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -keyout root.key -out root.crt -subj "/C=US/O=Fake Root/CN=Fake Root CA"

    # 2. Intermediate CA (Valid)
    openssl req -newkey rsa:2048 -nodes -keyout intermediate.key -out intermediate.csr -subj "/C=US/O=Fake Intermediate/CN=Fake Intermediate CA"
    echo "basicConstraints=CA:TRUE" > extfile.cnf
    openssl x509 -req -in intermediate.csr -CA root.crt -CAkey root.key -CAcreateserial -out intermediate.crt -days 3650 -extfile extfile.cnf

    # 3. Server Cert (Invalid - Signed by a completely different key, not the intermediate)
    openssl req -newkey rsa:2048 -nodes -keyout rogue.key -out rogue.csr -subj "/C=US/O=Rogue/CN=Rogue CA"
    openssl x509 -req -in rogue.csr -signkey rogue.key -out rogue.crt -days 3650
    openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/C=US/O=Target/CN=target.local"

    # Sign server with rogue CA, not intermediate
    openssl x509 -req -in server.csr -CA rogue.crt -CAkey rogue.key -CAcreateserial -out server.crt -days 3650

    chmod -R 777 /home/user
