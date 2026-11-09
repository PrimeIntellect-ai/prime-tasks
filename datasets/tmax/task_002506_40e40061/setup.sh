#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect curl rustc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/legacy_config_gen.sh
#!/bin/bash
read -p "Enter deployment environment: " env
if [ "$env" != "production" ]; then echo "Invalid env"; exit 1; fi

read -p "Enter service name: " svc
if [ "$svc" != "api_worker" ]; then echo "Invalid svc"; exit 1; fi

read -p "Confirm token generation (y/n): " confirm
if [ "$confirm" != "y" ]; then echo "Aborted"; exit 1; fi

# Generate random token
TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
echo "TOKEN=${TOKEN}" > /home/user/service_config.txt
echo "Configuration generated."
EOF

    chmod +x /home/user/legacy_config_gen.sh
    chmod -R 777 /home/user
