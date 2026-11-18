#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect g++ acl
    pip3 install pytest

    mkdir -p /home/user/.ssh

    cat << 'EOF' > /home/user/legacy_metrics_cli
#!/bin/bash
read -p "Username: " user
if [ "$user" != "admin" ]; then
    echo "Access Denied"
    exit 1
fi
read -p "PIN: " pin
if [ "$pin" != "1234" ]; then
    echo "Access Denied"
    exit 1
fi
echo "--- METRICS START ---"
echo "CPU_LOAD=45"
echo "MEM_MB=1000"
echo "DISK_IO=23"
echo "MEM_MB=2000"
echo "NET_TX=555"
echo "MEM_MB=1500"
echo "--- METRICS END ---"
EOF
    chmod +x /home/user/legacy_metrics_cli

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
