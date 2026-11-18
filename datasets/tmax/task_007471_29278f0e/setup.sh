#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang tar gzip
pip3 install pytest

useradd -m -s /bin/bash user || true

# 1. Create the changelog content in UTF-8
cat << 'EOF' > /tmp/changelog_utf8.txt
--- RECORD START ---
Version: 101
Author: Alice Admin
Changes:
 - Updated firewall rules
 - Opened port 443
 - Closed port 80
--- RECORD END ---
--- RECORD START ---
Version: 102
Author: Bob Backup
Changes:
 - Configured symlink traversal
 - Added infinite loop detection
--- RECORD END ---
EOF

# 2. Convert to UTF-16LE
iconv -f UTF-8 -t UTF-16LE /tmp/changelog_utf8.txt > /tmp/changelog.txt

# 3. Create the directory structure and symlink loops
mkdir -p /tmp/archive_prep/dirA/dirB
cp /tmp/changelog.txt /tmp/archive_prep/changelog.txt
ln -s ../../dirA /tmp/archive_prep/dirA/dirB/loop_link

# 4. Create the tarball
cd /tmp/archive_prep
tar -czf /home/user/config_archive.tar.gz *
cd ~
rm -rf /tmp/archive_prep /tmp/changelog_utf8.txt /tmp/changelog.txt

chmod -R 777 /home/user
