#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect
    pip3 install pytest pexpect

    mkdir -p /home/user/restore_dir
    chmod 755 /home/user/restore_dir

    cat << 'EOF' > /home/user/legacy_restore.sh
#!/bin/bash
if [ "$TZ" != "Pacific/Honolulu" ]; then 
    echo "Error: Incorrect timezone. System requires Pacific/Honolulu for accurate timestamp parsing."
    exit 1
fi

echo -n "Enter backup archive password: "
read -s password
echo
if [ "$password" != "V@ult2024" ]; then 
    echo "Error: Bad password"
    exit 1
fi

echo -n "Enter target restore date (YYYY-MM-DD): "
read date
if [ "$date" != "2024-01-01" ]; then 
    echo "Error: No backup found for date"
    exit 1
fi

# Simulate extracting 512000 bytes of data
dd if=/dev/zero of=/home/user/restore_dir/restored_data.bin bs=1024 count=500 2>/dev/null
echo "Restore complete."
EOF

    chmod +x /home/user/legacy_restore.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
