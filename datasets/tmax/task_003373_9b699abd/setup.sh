#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential wget tar
pip3 install pytest

mkdir -p /home/user/raw_data
mkdir -p /home/user/results
mkdir -p /home/user/local/bin

cat << 'EOF' > /home/user/raw_data/exp1.txt
Exp1|12/31/2022|Alpha|12,50
Exp2|2023-01-01|Beta|10.00
Exp3|01/02/2023|Alpha|5,25
Exp4|2023-01-03|Gamma|invalid
Exp5|2023-01-04|Beta|20.00
EOF

cat << 'EOF' > /home/user/raw_data/exp2.txt
Exp6|10/15/2023|Alpha|3.25
Exp7|2023-10-16|Beta|15,50
Exp8|10/17/2023|Gamma|100.00
Exp9|2023-10-18||45.00
Exp10|2023-10-19|Gamma|200,50
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
