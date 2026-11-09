#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_audit.log
[2023-10-12 14:02:11] AUTH_SUCCESS user=admin ip=192.168.1.50
[2023-10-12 14:15:33] AUTH_FAILED user=sys_backup hash=f18706c88ea760432bc97d9a13511ebddf9a1c1d81f124ba16a7ed22c4f8263c reason=expired_token
[2023-10-12 15:00:01] AUTH_SUCCESS user=db_service ip=10.0.0.5
EOF

    openssl req -x509 -newkey rsa:2048 -keyout /tmp/temp_key.pem -out /tmp/temp_cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=legacy.local"
    openssl pkcs12 -export -out /home/user/legacy_store.p12 -inkey /tmp/temp_key.pem -in /tmp/temp_cert.pem -passout pass:7391_backup
    rm /tmp/temp_key.pem /tmp/temp_cert.pem

    chmod -R 777 /home/user
