#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/raw_logs.csv
log_id,timestamp,sensor_id,message
1,1000,S1,Temperature high
2,1001,S1,Temperature high
3,1002,S1,Temperature hihg
4,1003,S2,Pressure normal
5,1004,S3,Valve stuck open
6,1005,S3,Valve stuck open
7,1006,S3,Valve stuck opne
8,1007,S4,Connection lost
9,1008,S5,Unknown error occurred
10,1009,S6,All systems go
11,1010,S1,Normal
EOF

cat << 'EOF' > /home/user/sensors.json
[
  {"sensor_id": "S1", "region": "Zone_A"},
  {"sensor_id": "S2", "region": "Zone_A"},
  {"sensor_id": "S3", "region": "Zone_B"},
  {"sensor_id": "S4", "region": "Zone_C"},
  {"sensor_id": "S5", "region": "Zone_C"},
  {"sensor_id": "S99", "region": "Zone_X"}
]
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
