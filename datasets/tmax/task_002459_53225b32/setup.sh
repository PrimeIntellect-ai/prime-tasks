#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip e2fsprogs tar gzip
pip3 install pytest pexpect

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/system_fstab
/dev/sda1 / ext4 defaults 1 1
/dev/sdb1 /data xfs defaults 0 2
EOF

mkdir -p /home/user/app_data
echo '{"dummy": "config"}' > /home/user/app_data/config.json
echo 'dummy data' > /home/user/app_data/data.bin

cat << 'EOF' > /home/user/legacy_backup.sh
#!/bin/bash
echo "WARN: Key-based login silently rejected. Falling back to interactive mode."
read -p "Password: " pswd
if [ "$pswd" != "SecretPass99" ]; then
    echo "Auth failed."
    exit 1
fi
read -p "Source path: " src
if [ ! -d "$src" ]; then
    echo "Source missing."
    exit 1
fi
read -p "Destination tarball: " dest
tar -czf "$dest" -C "$src" .
echo "Backup complete."
EOF

chmod +x /home/user/legacy_backup.sh

chmod -R 777 /home/user
