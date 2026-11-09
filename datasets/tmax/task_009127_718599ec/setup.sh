#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect gawk logrotate
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_restore.sh
#!/bin/bash
read -p "Enter decryption passphrase: " pass
if [ "$pass" != "secure_backup_2024" ]; then
    echo "[ERROR] Invalid passphrase" >> /home/user/restore_activity.log
    exit 1
fi

read -p "Target restore path: " path
if [ "$path" != "/home/user/recovered_data" ]; then
    echo "[ERROR] Invalid path" >> /home/user/restore_activity.log
    exit 1
fi

read -p "Proceed with restore? (yes/no): " proceed
if [ "$proceed" != "yes" ]; then
    echo "[WARN] Aborted" >> /home/user/restore_activity.log
    exit 1
fi

mkdir -p "$path"
echo "2024-10-24 10:00:01 INFO Started restore" > /home/user/restore_activity.log
echo "2024-10-24 10:00:02 [RESTORED] FILE /home/user/recovered_data/config.yml success" >> /home/user/restore_activity.log
echo "2024-10-24 10:00:03 [RESTORED] FILE /home/user/recovered_data/database.db success" >> /home/user/restore_activity.log
echo "2024-10-24 10:00:04 INFO Checking integrity" >> /home/user/restore_activity.log
echo "2024-10-24 10:00:05 [RESTORED] FILE /home/user/recovered_data/images.tar.gz success" >> /home/user/restore_activity.log
echo "2024-10-24 10:00:06 INFO Finished restore" >> /home/user/restore_activity.log
EOF

    chmod +x /home/user/legacy_restore.sh
    chown user:user /home/user/legacy_restore.sh

    chmod -R 777 /home/user
