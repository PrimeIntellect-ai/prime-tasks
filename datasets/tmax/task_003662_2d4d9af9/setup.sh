#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/monitored_data/app_configs/nested
    mkdir -p /home/user/archive

    dd if=/dev/urandom of=/home/user/monitored_data/app_configs/small_config.txt bs=1024 count=10 status=none
    dd if=/dev/urandom of=/home/user/monitored_data/app_configs/large_db.sqlite bs=1024 count=120 status=none
    dd if=/dev/urandom of=/home/user/monitored_data/app_configs/nested/settings.json bs=1024 count=45 status=none

    ln -s /home/user/monitored_data/app_configs /home/user/monitored_data/app_configs/nested/loop_link

    echo "/home/user/monitored_data/app_configs" > /home/user/watch_list.txt

    cat << 'EOF' > /home/user/config_tracker.sh
#!/bin/bash
ARCHIVE_DIR="/home/user/archive"
mkdir -p "$ARCHIVE_DIR"

while IFS= read -r dir; do
    # Broken: follows symlinks infinitely
    find -L "$dir" -type f | while IFS= read -r file; do
        cp "$file" "$ARCHIVE_DIR/"
    done
done < "/home/user/watch_list.txt"
EOF

    chmod +x /home/user/config_tracker.sh
    chown -R user:user /home/user
    chmod -R 777 /home/user
