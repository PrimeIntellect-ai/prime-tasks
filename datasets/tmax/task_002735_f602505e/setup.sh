#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc build-essential
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/flaky_qemu.sh
#!/bin/bash
COUNT_FILE="/home/user/.fail_count"
if [ ! -f "$COUNT_FILE" ]; then
    echo 1 > "$COUNT_FILE"
    exit 1
fi
COUNT=$(cat "$COUNT_FILE")
if [ "$COUNT" -lt 3 ]; then
    echo $((COUNT + 1)) > "$COUNT_FILE"
    exit 1
else
    exit 0
fi
EOF

chmod +x /home/user/flaky_qemu.sh

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
