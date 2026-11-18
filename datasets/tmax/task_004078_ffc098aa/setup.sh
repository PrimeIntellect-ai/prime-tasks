#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    mkdir -p /home/user

    cat << 'EOF' > /home/user/iot_init.sh
#!/bin/bash
read -p "Configuration ready? [y/N]: " ready
if [ "$ready" != "y" ]; then 
    echo "Aborted."
    exit 1
fi

read -p "Device ID: " dev_id

if [ "$TZ" = "Antarctica/Troll" ] && [ "$LC_TIME" = "fr_FR.UTF-8" ]; then
    echo "$dev_id deployed at $TZ with $LC_TIME" > /home/user/iot_deploy.log
else
    echo "Deployment failed due to bad environment settings." > /home/user/iot_deploy.log
    echo "Got TZ=$TZ and LC_TIME=$LC_TIME" >> /home/user/iot_deploy.log
    exit 1
fi
EOF

    chmod +x /home/user/iot_init.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
