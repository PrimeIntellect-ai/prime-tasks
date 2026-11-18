#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/app.conf
insecure_mode=true
log_level=debug
EOF

    cat << 'EOF' > /home/user/legacy_deploy.sh
#!/bin/bash
# Simulates an interactive, flaky legacy deployment script
read -p "Enter hardening passphrase: " PASS
if [ "$PASS" != "S3cr3tH4rd3n!" ]; then
    echo "Invalid passphrase"
    exit 2
fi

COUNT_FILE="/home/user/.deploy_count"
if [ ! -f "$COUNT_FILE" ]; then
    echo 1 > "$COUNT_FILE"
    echo "Fatal Error: Network timeout during sync"
    exit 1
fi

COUNT=$(cat "$COUNT_FILE")
if [ "$COUNT" -lt 3 ]; then
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$COUNT_FILE"
    echo "Fatal Error: Database lock contention"
    exit 1
fi

echo "Deployment Secure"
exit 0
EOF

    chmod +x /home/user/legacy_deploy.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
