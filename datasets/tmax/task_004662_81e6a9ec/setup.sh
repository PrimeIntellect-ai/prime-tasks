#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/data/subdir

# Create older file
echo -n "old content" > /home/user/data/file1.txt
touch -d "@1693526400" /home/user/data/file1.txt

# Create newer files
echo -n "new data 1" > /home/user/data/file2.txt
touch -d "@1696982400" /home/user/data/file2.txt

echo -n "new data 2" > /home/user/data/subdir/file3.txt
touch -d "@1697760000" /home/user/data/subdir/file3.txt

# Create symlink loop
ln -s /home/user/data /home/user/data/loop

# Create the backup log
cat << 'EOF' > /home/user/backup_history.log
--- Backup Record ---
Status: SUCCESS
Timestamp: 1690000000
Files: 10
---------------------
--- Backup Record ---
Status: SUCCESS
Timestamp: 1696161600
Files: 5
---------------------
--- Backup Record ---
Status: FAILED
Timestamp: 1697000000
Files: 0
---------------------
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
