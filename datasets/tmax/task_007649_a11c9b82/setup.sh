#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/config_changes.csv
ChangeID,Timestamp,User,Diff
C001,2023-10-01T10:00:00Z,alice,"- IP: 10.0.0.1
+ IP: 192.168.1.100"
C002,2023-10-01T10:05:00Z,bob,"+ PORT: 8080"
C003,2023-10-01T10:10:00Z,alice,"- PORT: 80
+ IP: 192.168.1.101
+ IP: 10.0.0.5
- IP: 192.168.1.200"
C004,2023-10-01T10:15:00Z,charlie,"Updated config without IP changes."
C005,2023-10-01T10:20:00Z,bob,"Minor tweak
+ IP: 172.16.0.42
Done."
C006,2023-10-01T10:25:00Z,alice,"+ IP: invalid.ip.address
+ IP: 8.8.8.8"
EOF

chmod -R 777 /home/user
