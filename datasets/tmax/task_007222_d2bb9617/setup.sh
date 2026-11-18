#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/extracted

    cat << 'EOF' > /home/user/dict.txt
password123
admin
admin123
spring2023
security2024
letmein
changeme
EOF

    echo "ROTATED_MASTER_KEY_SECRET_998877" > /home/user/.hidden_master_key

    # Generate Certificates
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/ca.key -out /home/user/ca.crt -days 365 -nodes -subj "/C=US/ST=CA/L=San Francisco/O=Global Security Inc/OU=IT/CN=RootCA"
    openssl req -newkey rsa:2048 -keyout /home/user/old_key.pem -out /home/user/old_csr.pem -nodes -subj "/C=US/ST=CA/L=San Francisco/O=Global Security Inc/OU=Web/CN=legacy.local"
    openssl x509 -req -in /home/user/old_csr.pem -CA /home/user/ca.crt -CAkey /home/user/ca.key -set_serial 0x01ABCDEF -out /home/user/old_cert.pem -days 365

    # Create encrypted zip
    echo "BACKUP_PRIVATE_KEY_CONTENTS" > /home/user/backup_key.pem
    cd /home/user && zip -P security2024 legacy_credentials.zip backup_key.pem
    rm /home/user/backup_key.pem

    # Create vulnerable rotate script
    cat << 'EOF' > /home/user/rotate_service.sh
#!/bin/bash
if [ "$#" -ne 1 ]; then 
    echo "Usage: $0 <payload_file>"
    exit 1
fi
PAYLOAD=$(cat "$1")
# Vulnerable command injection via eval
eval "echo \"Rotating credentials for metadata: $PAYLOAD\" >> /home/user/rotation.log"
EOF
    chmod +x /home/user/rotate_service.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user
