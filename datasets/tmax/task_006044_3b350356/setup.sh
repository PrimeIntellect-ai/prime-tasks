#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/sensor_data.csv
site_id,date,temp,humidity,pm25
S1,2023-01-01,20.5,50.1,15.2
S1,2023-01-02,21.0,49.8,14.8
S2,2023-01-01,18.0,60.5,8.5
S2,2023-01-02,17.5,61.0,9.0
S3,2023-01-01,25.0,40.0,25.0
S3,2023-01-02,24.5,41.2,26.1
S4,2023-01-01,15.0,70.0,5.0
S4,2023-01-02,15.5,68.5,5.5
EOF

cat << 'EOF' > /home/user/site_info.json
[
  {"site_id": "S1", "type": "Suburban", "elevation": 150},
  {"site_id": "S2", "type": "Rural", "elevation": 300},
  {"site_id": "S3", "type": "Urban", "elevation": 50},
  {"site_id": "S4", "type": "Rural", "elevation": 500}
]
EOF

chmod -R 777 /home/user
