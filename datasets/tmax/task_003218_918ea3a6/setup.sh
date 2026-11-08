#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 file
pip3 install pytest

mkdir -p /home/user/raw_data

cat << 'EOF' > /home/user/raw_data/data_A.csv
id,timestamp,server_name,response_time_ms
1,2023-10-01T10:00:00Z,srv1,150
2,2023-10-01T10:01:00Z,srv1,155
4,2023-10-01T10:03:00Z,srv1,160
EOF

cat << 'EOF' | iconv -f UTF-8 -t UTF-16LE > /home/user/raw_data/data_B.csv
id,timestamp,server_name,response_time_ms
3,2023-10-01T10:02:00Z,srv1,152
5,2023-10-01T10:04:00Z,srv1,500
EOF

cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/raw_data/data_C.csv
id,timestamp,server_name,response_time_ms
6,2023-10-01T10:05:00Z,srv1,480
7,2023-10-01T10:06:00Z,srv1,1500
8,2023-10-01T10:07:00Z,srv1,200
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
