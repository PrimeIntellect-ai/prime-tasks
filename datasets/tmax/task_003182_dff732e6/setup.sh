#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sudo gcc libcjson-dev tar
pip3 install pytest

useradd -m -s /bin/bash user || true
echo "user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

mkdir -p /home/user/dataset_raw

cat << 'EOF' > /home/user/dataset_raw/config.json
[
  {
    "filename": "sensor_A.csv",
    "encoding": "ISO-8859-1"
  },
  {
    "filename": "sensor_B.csv",
    "encoding": "UTF-16LE"
  }
]
EOF

cat << 'EOF' > /tmp/sensor_A.utf8.csv
ID,Measurement,Notes
1,10.5,resumé
2,20.2,café
EOF

iconv -f UTF-8 -t ISO-8859-1 /tmp/sensor_A.utf8.csv > /home/user/dataset_raw/sensor_A.csv

cat << 'EOF' > /tmp/sensor_B.utf8.csv
ID,Notes,Measurement
1,naïve,100.1
2,façade,50.3
EOF

iconv -f UTF-8 -t UTF-16LE /tmp/sensor_B.utf8.csv > /home/user/dataset_raw/sensor_B.csv

chmod -R 777 /home/user
