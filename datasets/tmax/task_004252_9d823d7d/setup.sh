#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo rustc tar gzip
pip3 install pytest

mkdir -p /home/user/old_records/server1/logs
mkdir -p /home/user/old_records/server2/archive/deep

cat << 'EOF' > /home/user/old_records/server1/logs/app.log
[INFO] Application started
[VERBOSE-DUMP] state={memory: 1024MB, cpu: 12%}
[VERBOSE-DUMP] state={memory: 1025MB, cpu: 14%}
[WARN] Connection timeout
[VERBOSE-DUMP] state={memory: 1024MB, cpu: 12%}
[INFO] Retrying connection
EOF

cat << 'EOF' > /home/user/old_records/server2/archive/deep/old_data.txt
Data line 1
[VERBOSE-DUMP] dump_id=99281
Data line 2
[VERBOSE-DUMP] dump_id=99282
[VERBOSE-DUMP] dump_id=99283
Data line 3
EOF

cat << 'EOF' > /home/user/old_records/server2/archive/ignore_me.csv
id,name
1,alice
2,bob
[VERBOSE-DUMP] this should not be removed because it's a .csv file
EOF

cat << 'EOF' > /home/user/old_records/root_level.log
[VERBOSE-DUMP] init
[INFO] Root initialized
[VERBOSE-DUMP] destroy
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
