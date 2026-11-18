#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect socat acl netcat-openbsd g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    useradd -m guest || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/iot_provision.sh
#!/bin/bash
echo -n "Enter Device ID: "
read device_id
echo -n "Enter Provisioning PIN: "
read -s pin
echo ""
if [ "$pin" == "4921" ]; then
    echo "TOKEN=secure_token_12345" > /home/user/device.conf
    echo "DEVICE=$device_id" >> /home/user/device.conf
    echo "Provisioning successful."
else
    echo "Invalid PIN."
    exit 1
fi
EOF

    chmod +x /home/user/iot_provision.sh

    chmod -R 777 /home/user
