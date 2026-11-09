#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ expect
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/restore_tool
#!/bin/bash
echo -n "Are you sure you want to restore? [y/N]: "
read answer
if [[ "$answer" != "y" ]]; then
    echo "Aborted."
    exit 1
fi
echo -n "Enter path to backup archive: "
read archive_path
if [[ ! -f "$archive_path" ]]; then
    echo "Archive not found."
    exit 1
fi
tar -xzf "$archive_path" -C /
echo "Restore complete."
EOF

chmod +x /home/user/restore_tool

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
