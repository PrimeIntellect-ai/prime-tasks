#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zip tar
pip3 install pytest

mkdir -p /home/user/storage/logs/
cd /home/user/storage/logs/

# Create Archive A
mkdir -p tmp_a
cat << 'EOF' > tmp_a/data.json
[
  {"level": "INFO", "size_bytes": 1024, "msg": "Started"},
  {"level": "FATAL", "size_bytes": 50000, "msg": "Core dump A"},
  {"level": "ERROR", "size_bytes": 2048, "msg": "Network timeout"}
]
EOF
cd tmp_a && zip inner_A.zip data.json >/dev/null && cd ..
tar -czf logs_A.tar.gz -C tmp_a inner_A.zip
rm -rf tmp_a

# Create Archive B
mkdir -p tmp_b
cat << 'EOF' > tmp_b/data1.json
[
  {"level": "FATAL", "size_bytes": 15000, "msg": "OOM"},
  {"level": "FATAL", "size_bytes": 5000, "msg": "Segfault"}
]
EOF
cat << 'EOF' > tmp_b/data2.json
[
  {"level": "WARN", "size_bytes": 100, "msg": "Deprecated"}
]
EOF
cd tmp_b && zip inner_B.zip data1.json data2.json >/dev/null && cd ..
tar -czf logs_B.tar.gz -C tmp_b inner_B.zip
rm -rf tmp_b

# Create Archive C
mkdir -p tmp_c
cat << 'EOF' > tmp_c/metrics.json
[
  {"level": "INFO", "size_bytes": 888, "msg": "Heartbeat"},
  {"level": "DEBUG", "size_bytes": 12, "msg": "Ping"}
]
EOF
cd tmp_c && zip inner_C.zip metrics.json >/dev/null && cd ..
tar -czf logs_C.tar.gz -C tmp_c inner_C.zip
rm -rf tmp_c

# Create Archive D (Nested deeply or multiple zips)
mkdir -p tmp_d
cat << 'EOF' > tmp_d/log.json
[
  {"level": "FATAL", "size_bytes": 9999, "msg": "Disk Failure"}
]
EOF
cd tmp_d && zip inner_D1.zip log.json >/dev/null && cd ..
tar -czf logs_D.tar.gz -C tmp_d inner_D1.zip
rm -rf tmp_d

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/storage
chmod -R 777 /home/user
