#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/setup
mkdir -p /home/user/.config
mkdir -p /home/user/secure_storage

dd if=/dev/zero of=/home/user/secure_storage/dummy_data.bin bs=1024 count=5500 2>/dev/null

cat << 'EOF' > /home/user/setup/legacy_config.sh
#!/bin/bash
echo "Starting legacy configuration wizard..."
read -p "Enter desired timezone (e.g. UTC, EST): " tz
read -p "Enter desired locale (e.g. en_US.UTF-8): " loc
read -p "Confirm changes? (y/n): " confirm

if [ "$confirm" = "y" ]; then
    echo "TZ=$tz" > /home/user/.config/user_locale.conf
    echo "LANG=$loc" >> /home/user/.config/user_locale.conf
    echo "Configuration saved."
else
    echo "Aborted."
    exit 1
fi
EOF
chmod +x /home/user/setup/legacy_config.sh

chown -R user:user /home/user/setup /home/user/secure_storage /home/user/.config
chmod -R 777 /home/user
