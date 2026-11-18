#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/users.csv
user_id,username,multiplier
1,alice,1.5
2,bob,0.8
3,charlie,2.0
4,david,0.5
EOF

cat << 'EOF' > /tmp/scores_utf8.csv
user_id,score1,score2,score3
1,10,20,30
2,5,5,5
3,0,10,0
4,100,0,0
EOF

iconv -f UTF-8 -t UTF-16LE /tmp/scores_utf8.csv > /home/user/scores.csv
rm /tmp/scores_utf8.csv

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
