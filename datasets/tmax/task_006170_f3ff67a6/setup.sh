#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    mkdir -p /home/user/config /home/user/bin /home/user/run/containers

    cat << 'EOF' > /home/user/config/limits.json
{
    "max_storage_mb": 1024,
    "cpu_shares": 512
}
EOF

    cat << 'EOF' > /home/user/bin/provisioner.sh
#!/bin/bash

if [ "$1" == "--stop" ]; id="$2"; then
    if [ -z "$id" ]; then
        echo "Error: Missing ID"
        exit 1
    fi
    if [ -f "/home/user/run/containers/${id}.pid" ]; then
        rm -f "/home/user/run/containers/${id}.pid"
        echo "Container $id stopped."
        exit 0
    else
        echo "Error: Container $id not found."
        exit 1
    fi
fi

echo -n "Enter container name: "
read name
echo -n "Enter storage limit (MB): "
read storage
echo -n "Enable read-only rootfs? (y/n): "
read ro_root

if [[ "$ro_root" != "y" && "$ro_root" != "n" ]]; then
    echo "Invalid option for read-only rootfs."
    exit 1
fi

uuid=$(cat /proc/sys/kernel/random/uuid)
echo $$ > "/home/user/run/containers/${uuid}.pid"
echo "Initializing isolated environment for $name..."
sleep 1
echo "Applying quota: ${storage}MB"
echo "Successfully started container [ID: ${uuid}]"
EOF
    chmod +x /home/user/bin/provisioner.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
