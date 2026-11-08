#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc make
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/config_events.csv
1500200,theme,dark
1500800,timeout,30
1501000,retries,3
1501150,theme,light
1502400,timeout,60
1504000,retries,5
EOF

chmod -R 777 /home/user
