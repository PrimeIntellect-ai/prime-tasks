#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

mkdir -p /home/user/config_backups
cd /home/user/config_backups

# Create backup_1
mkdir -p /tmp/b1
cat << 'EOF' > /tmp/b1/changes.log
START_CHANGE
Author: Alice
Date: 2023-01-01
Files: 2
Details:
Updated nginx.conf
Added new route
END_CHANGE

Random text here

START_CHANGE
Author: Bob
Date: 2023-01-02
Files: 1
Details:
Fixed typo
END_CHANGE

START_CHANGE
Author: Alice
Date: 2023-01-03
Files: 5
Details:
Major refactor
END_CHANGE
EOF
tar -czf backup_1.tar.gz -C /tmp/b1 changes.log

# Create backup_2 (clog)
mkdir -p /tmp/b2
cat << 'EOF' > /tmp/b2/changes.log
START_CHANGE
Author: Charlie
Date: 2023-02-01
Files: 1
Details:
Init
END_CHANGE

START_CHANGE
Author: Charlie
Date: 2023-02-02
Files: 2
Details:
Added DB config
END_CHANGE

START_CHANGE
Author: Alice
Date: 2023-02-03
Files: 1
Details:
Tweaked DB config
END_CHANGE
EOF
tar -czf /tmp/backup_2.tar.gz -C /tmp/b2 changes.log
base64 /tmp/backup_2.tar.gz > backup_2.clog

# Create backup_3 (invalid checksum)
mkdir -p /tmp/b3
cat << 'EOF' > /tmp/b3/changes.log
START_CHANGE
Author: Eve
Date: 2023-03-01
Files: 100
Details:
Hacked the mainframe
END_CHANGE
EOF
tar -czf backup_3.tar.gz -C /tmp/b3 changes.log

# Generate checksums.txt
sha256sum backup_1.tar.gz > checksums.txt
sha256sum backup_2.clog >> checksums.txt
# Add a fake checksum for backup_3
echo "0000000000000000000000000000000000000000000000000000000000000000  backup_3.tar.gz" >> checksums.txt

rm -rf /tmp/b1 /tmp/b2 /tmp/b3 /tmp/backup_2.tar.gz

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
