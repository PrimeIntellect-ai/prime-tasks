#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/app_logs/dir1/sub
mkdir -p /home/user/app_logs/dir2
mkdir -p /home/user/app_logs/dir3

cat << 'EOF' > /home/user/setup.py
import gzip
import os

# dir1/a.wal.gz
with gzip.open('/home/user/app_logs/dir1/a.wal.gz', 'wt') as f:
    f.write("1|2023-10-01T10:00:00|INFO|Started\n")
    f.write("5|2023-10-01T10:05:00|ERROR|Disk full\n")

# dir1/sub/b.wal
with open('/home/user/app_logs/dir1/sub/b.wal', 'w') as f:
    f.write("2|2023-10-01T10:01:00|DEBUG|Loading\n")
    f.write("3|2023-10-01T10:02:00|FATAL|Kernel panic\n")

# dir2/c.wal.gz
with gzip.open('/home/user/app_logs/dir2/c.wal.gz', 'wt') as f:
    f.write("4|2023-10-01T10:03:00|INFO|Retrying\n")
    f.write("7|2023-10-01T10:07:00|ERROR|Network down\n")

# dir3/d.wal
with open('/home/user/app_logs/dir3/d.wal', 'w') as f:
    f.write("6|2023-10-01T10:06:00|WARN|High CPU\n")

# root.wal.gz
with gzip.open('/home/user/app_logs/root.wal.gz', 'wt') as f:
    f.write("8|2023-10-01T10:08:00|FATAL|OOM\n")
    f.write("9|2023-10-01T10:09:00|INFO|Shutdown\n")
EOF

python3 /home/user/setup.py
rm /home/user/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
