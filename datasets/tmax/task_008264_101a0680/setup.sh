#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip binutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/workspace/raw_data
cd /home/user/workspace

cat << 'EOF' > rules.json
{
  "datasets": ["data1.csv", "data2.csv"],
  "binaries": ["worker", "dummy_arm"],
  "logs": ["sys.log", "debug.log"]
}
EOF

cat << 'EOF' > raw_data/data1.csv
id,timestamp,status,message
1,1000,OK,started
2,1001,ERROR,failed connection
3,1002,OK,reconnected
4,1003,ERROR,timeout
EOF

cat << 'EOF' > raw_data/data2.csv
id,timestamp,status,message
10,2000,OK,init
11,2001,WARN,slow
12,2002,ERROR,crash
EOF

cp /bin/ls raw_data/worker

python3 -c '
with open("raw_data/dummy_arm", "wb") as f:
    f.write(b"\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00\x01\x00\x00\x00")
'
chmod +x raw_data/dummy_arm

echo "log entry 1" > raw_data/sys.log
echo "log entry 2" > raw_data/debug.log

chmod -R 777 /home/user
