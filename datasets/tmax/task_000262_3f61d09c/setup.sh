#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect cron
pip3 install pytest

mkdir -p /home/user/app/users/

cat << 'EOF' > /home/user/app/account-monitor.service
[Unit]
Description=Account Monitor Service
Wants=storage-init.service

[Service]
Type=simple
ExecStart=/home/user/app/check_quota.sh

[Install]
WantedBy=default.target
EOF

cat << 'EOF' > /home/user/app/provision.sh
#!/bin/bash
read -p "Enter Admin PIN: " pin
if [ "$pin" != "8821" ]; then
    echo "Invalid PIN."
    exit 1
fi
read -p "Action (1=Init, 2=Clear): " action
if [ "$action" == "1" ]; then
    echo "Initialization complete."
    exit 0
else
    echo "Unknown action."
    exit 1
fi
EOF
chmod +x /home/user/app/provision.sh

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
