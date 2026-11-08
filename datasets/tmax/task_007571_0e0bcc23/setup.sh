#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git expect
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/tools
    cat << 'EOF' > /home/user/tools/check_net.sh
#!/bin/bash
read -p "Enter username: " user
if [ "$user" != "admin" ]; then
    echo "Access denied."
    exit 1
fi
read -p "Enter pin: " pin
if [ "$pin" != "8492" ]; then
    echo "Invalid pin."
    exit 1
fi
read -p "Enter target file: " target
if [ -f "$target" ]; then
    echo "Network check passed for $target"
else
    echo "File not found: $target"
    exit 1
fi
EOF
    chmod +x /home/user/tools/check_net.sh

    chmod -R 777 /home/user
