#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup

    cat << 'EOF' > /home/user/backup/fstab.txt
/dev/sda1 / ext4 defaults 1 1
10.0.0.5:/shared /mnt/shared_nfs nfs defaults 0 0
tmpfs /run tmpfs rw,nosuid,nodev 0 0
10.0.0.6:/data /opt/app_data nfs ro,hard 0 0
/dev/sdb1 /var/log xfs defaults 0 2
EOF

    cat << 'EOF' > /home/user/backup/firewall.json
{
  "blocked_ips": [
    "192.168.1.50",
    "10.5.5.1",
    "172.16.0.4"
  ]
}
EOF

    cat << 'EOF' > /home/user/backup/flaky_app.sh
#!/bin/bash
# File to keep track of run count
COUNTER_FILE="/home/user/backup/.run_count"

if [ ! -f "$COUNTER_FILE" ]; then
    echo "1" > "$COUNTER_FILE"
    exit 3
fi

COUNT=$(cat "$COUNTER_FILE")

if [ "$COUNT" -eq 1 ]; then
    echo "2" > "$COUNTER_FILE"
    exit 12
elif [ "$COUNT" -eq 2 ]; then
    echo "3" > "$COUNTER_FILE"
    exit 7
else
    echo "4" > "$COUNTER_FILE"
    exit 0
fi
EOF

    chmod +x /home/user/backup/flaky_app.sh

    chmod -R 777 /home/user
