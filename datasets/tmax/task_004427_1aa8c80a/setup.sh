#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/report_template.txt
=== NETWORK LATENCY REPORT ===
Date: 2023-10-25
------------------------------
EOF
printf "{%sREPORTS%s}\n" "{" "}" >> /home/user/report_template.txt
cat << 'EOF' >> /home/user/report_template.txt
==============================
EOF

cat << 'EOF' > /home/user/raw_metrics_utf8.csv
Timestamp,ServerAlpha,ServerBeta,ServerGamma
1622540000,45.5,102.0,-5.0
1622540060,50.0,1500.0,88.2
1622540120,48.5,98.0,90.1
EOF

iconv -f UTF-8 -t UTF-16LE /home/user/raw_metrics_utf8.csv > /home/user/raw_metrics.csv
rm /home/user/raw_metrics_utf8.csv

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
