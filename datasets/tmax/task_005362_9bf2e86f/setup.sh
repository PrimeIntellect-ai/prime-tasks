#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/app-installer.sh
#!/bin/bash
read -p "Enter instance name: " inst
read -p "Enter port number: " port
read -p "Enable verbose mode? (y/n): " verb

if [ "$inst" = "prod-worker" ] && [ "$port" = "9090" ] && [ "$verb" = "y" ]; then
    echo "Installation successful."
    mkdir -p /home/user/volume
    cat << 'INNER_EOF' > /home/user/service.sh
#!/bin/bash
while true; do
    head -c 5000 /dev/urandom >> /home/user/volume/data.bin
    sleep 0.1
done
INNER_EOF
    chmod +x /home/user/service.sh
else
    echo "Installation failed. Incorrect parameters."
    exit 1
fi
EOF
    chmod +x /home/user/app-installer.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
