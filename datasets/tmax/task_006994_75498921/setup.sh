#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk
pip3 install pytest pandas numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/sensor_a.csv
ts,f1,f2
1,10.5,2.0
2,11.0,0.0
3,9.5,1.5
4,12.1,3.0
5,8.0,2.0
EOF

cat << 'EOF' > /home/user/sensor_b.csv
ts,f3
1,9.0
2,11.0
3,10.0
4,10.0
5,7.8
EOF

chmod -R 777 /home/user
