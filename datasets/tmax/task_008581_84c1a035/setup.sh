#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/deploy.sh
#!/bin/bash
# Broken deployment script
/home/user/rotate.sh
echo "Starting server on port $APP_PORT with cert $TLS_DIR/server.crt" >> $APP_LOG_DIR/server.log
EOF
    chmod +x /home/user/deploy.sh

    chmod -R 777 /home/user
