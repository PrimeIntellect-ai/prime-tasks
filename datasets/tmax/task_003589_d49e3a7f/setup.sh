#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential gawk coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/raw_sensors.tsv
1672531200	Tokyo/東京	10.0	OK
1672533000	Tokyo/東京	12.0	OK
1672534800	Tokyo/東京	11.0	OK
1672542000	Tokyo/東京	9.0	OK
1672531200	Paris/Île-de-France	5.0	OK
1672531300	Paris/Île-de-France	5.5	ERR: volt
1672534800	Paris/Île-de-France	6.0	OK
1672538400	Paris/Île-de-France	7.5	OK
1672531200	NewYork/NYC	-2.0	OK
EOF

chmod -R 777 /home/user
