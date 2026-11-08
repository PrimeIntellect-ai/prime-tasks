#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar gzip file
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/incoming
mkdir -p /home/user/temp_setup

# Create doc_rules.ini
cat << 'EOF' > /home/user/doc_rules.ini
Incoming=/home/user/incoming
Processed=/home/user/processed
Archives=/home/user/archives
Snapshot=/home/user/archives/backup.snar
EOF

# Create dummy markdown files
echo -e "# Introduction\nWelcome to the docs." > /home/user/temp_setup/intro.md
echo -e "# Conclusion\nEnd of docs." > /home/user/temp_setup/conclusion.md

# Create tar and tar.gz files
cd /home/user/temp_setup
tar -cf /home/user/incoming/doc_dump_1 intro.md
tar -czf /home/user/incoming/doc_dump_2 conclusion.md

# Cleanup temp
rm -rf /home/user/temp_setup
cd /home/user

chmod -R 777 /home/user
