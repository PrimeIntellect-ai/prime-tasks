#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang expect curl
    pip3 install pytest

    mkdir -p /home/user/storage/pool1 /home/user/storage/pool2 /home/user/tools

    cat << 'EOF' > /home/user/tools/allocator
#!/bin/bash
echo -n "Enter pool to manage: "
read POOL
echo -n "Select action (expand/shrink): "
read ACTION
echo -n "Confirm (y/n): "
read CONFIRM
echo "Action $ACTION applied to $POOL."
EOF
    chmod +x /home/user/tools/allocator

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
