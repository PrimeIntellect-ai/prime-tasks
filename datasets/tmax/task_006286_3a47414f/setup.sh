#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas

mkdir -p /home/user/data
mkdir -p /home/user/output

cat << 'EOF' > /home/user/data/factory_wide.csv
timestamp,factory,temp,pressure,humidity
2023-10-01T10:00:00Z,F1,25.4,101.2,45.0
2023-10-01T10:05:00Z,F1,26.1,100.9,46.5
2023-10-01T10:10:00Z,F1,150.0,101.0,45.0
2023-10-01T10:15:00Z,F1,24.8,115.0,55.0
EOF

cat << 'EOF' > /home/user/data/factory_long.csv
time_log,fid,metric,val
2023-10-01T10:00:00Z,F2,temp,22.1
2023-10-01T10:00:00Z,F2,pressure,99.8
2023-10-01T10:00:00Z,F2,humidity,50.0
2023-10-01T10:05:00Z,F2,temp,22.3
2023-10-01T10:05:00Z,F2,pressure,100.1
2023-10-01T10:05:00Z,F2,humidity,105.0
2023-10-01T10:20:00Z,F2,temp,21.0
2023-10-01T10:20:00Z,F2,pressure,102.0
EOF

cat << 'EOF' > /home/user/data/rules.json
{
  "temp": {"min": -10.0, "max": 60.0},
  "pressure": {"min": 80.0, "max": 120.0},
  "humidity": {"min": 0.0, "max": 100.0}
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
