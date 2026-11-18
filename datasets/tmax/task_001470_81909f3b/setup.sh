#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect haproxy curl
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/legacy_api.sh
#!/bin/bash
read -p "Enter SRE passcode: " pass
if [ "$pass" != "SRE-8891" ]; then
    echo "Auth failed."
    exit 1
fi
read -p "Start server? (y/n): " confirm
if [ "$confirm" == "y" ]; then
    echo "Starting on port 9000..."
    exec python3 -m http.server 9000
fi
EOF
    chmod +x /home/user/legacy_api.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
