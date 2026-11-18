#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zip tar gcc libc-bin
pip3 install pytest

mkdir -p /home/user/backup_ops
cd /home/user/backup_ops

# Create the log file in ISO-8859-1
cat << 'EOF' > legacy_app.log
Line 1: Normal system boot
Line 2: FATAL database connection failed
Line 3: Retrying...
Line 4: FATAL disk write error on /dev/sdb1
Line 5: User admin logged in
Line 6: FATAL memory corruption detected
Line 7: Shutting down safely
EOF
iconv -f UTF-8 -t ISO-8859-1 legacy_app.log -o legacy_app_iso.log
mv legacy_app_iso.log legacy_app.log

# Create nested archives
zip logs_2022.zip legacy_app.log
tar -czvf master_backup.tar.gz logs_2022.zip
rm legacy_app.log logs_2022.zip

# Create initial catalog
echo "master_backup.tar.gz: indexed" > catalog.txt

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
