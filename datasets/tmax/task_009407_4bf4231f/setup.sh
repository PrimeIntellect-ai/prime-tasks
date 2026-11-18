#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar
pip3 install pytest

mkdir -p /home/user/incoming
mkdir -p /home/user/staging
mkdir -p /home/user/json_logs

cat << 'EOF' > /home/user/incoming/server1.csv
time,event
100,start
101,stop
EOF

cat << 'EOF' > /home/user/incoming/server2.csv
time,event
100,start

101,stop

EOF

cat << 'EOF' > /home/user/incoming/server3.csv
time,event
200,start
EOF

cat << 'EOF' > /home/user/incoming/server4.csv
time,event
200,start
EOF

cd /home/user/incoming
tar -cf logs.tar server1.csv server2.csv server3.csv server4.csv
rm server1.csv server2.csv server3.csv server4.csv
cd /home/user

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
