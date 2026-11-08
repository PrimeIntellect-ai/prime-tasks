#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/upstream_configs
cat << 'EOF' > /home/user/upstream_configs/server1_changes.csv
2023-10-01, Nginx.conf , 15
10/02/2023, DB.conf, 12
2023-10-03, nginx.conf, 8
10/05/2023, APP.json, 25
EOF

cat << 'EOF' > /home/user/upstream_configs/server2_changes.csv
10/01/2023, APP.json, 5
2023-10-02, nginx.conf, 10
10/03/2023, app.JSON, 20
2023-10-04, Nginx.conf, 5
EOF

chmod -R 777 /home/user
