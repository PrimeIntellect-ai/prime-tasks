#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 cron gawk
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/raw.dat
162000|S1|12.5
162060|S2|45.0
162120|S3|8.2
162180|S1|55.1
162240|S2|22.4
162300|S3|33.3
EOF

chmod -R 777 /home/user
