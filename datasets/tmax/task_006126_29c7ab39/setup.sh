#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the Git repository and history
    mkdir -p /home/user/payment-service
    cd /home/user/payment-service
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > config.py
PORT = 8080
VOID_API_KEY = "sk_live_77a91b34f829c011x"
DEBUG = False
EOF
    git add config.py
    git commit -m "Initial commit with config"

    cat << 'EOF' > config.py
PORT = 8080
VOID_API_KEY = os.environ.get("VOID_API_KEY")
DEBUG = False
EOF
    git add config.py
    git commit -m "Remove hardcoded API key"

    # Create the memory dump
    dd if=/dev/urandom of=/home/user/payment.dump bs=1K count=100
    echo -n "CRITICAL_TXN:TXN-8849-ACBD-1102" >> /home/user/payment.dump
    dd if=/dev/urandom of=/tmp/temp.dump bs=1K count=100
    cat /tmp/temp.dump >> /home/user/payment.dump
    rm /tmp/temp.dump

    chmod -R 777 /home/user
