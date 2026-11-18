#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

mkdir -p /home/user/raw_data

cat << 'EOF' > /home/user/raw_data/part_01.json
[
  {"id": 101, "prior": 0.5, "likelihood": 0.8, "actual_class": 1},
  {"id": 102, "prior": 1.2, "likelihood": 0.5, "actual_class": 1},
  {"id": 103, "prior": 0.2, "likelihood": 0.1, "actual_class": 0}
]
EOF

cat << 'EOF' > /home/user/raw_data/part_02.json
[
  {"id": 201, "prior": 0.5, "likelihood": -0.1, "actual_class": 0},
  {"id": 202, "prior": 0.6, "likelihood": 0.7, "actual_class": 1},
  {"id": 203, "prior": 0.9, "likelihood": 0.9, "actual_class": 2}
]
EOF

cat << 'EOF' > /home/user/raw_data/part_03.json
[
  {"id": 301, "prior": 0.8, "likelihood": 0.4, "actual_class": 0},
  {"id": 302, "prior": 0.0, "likelihood": 1.0, "actual_class": 1}
]
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/raw_data
chmod -R 777 /home/user
