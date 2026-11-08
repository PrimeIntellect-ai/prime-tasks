#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zip unzip
pip3 install pytest

mkdir -p /home/user/dump_source
cd /home/user/dump_source

cat << 'EOF' > fileA.orig
[KEEP] Database_Host=localhost
[DROP] Temp_Cache=19283
[KEEP] Database_Port=5432
[DROP] User_Click_Event=true
EOF

cat << 'EOF' > fileB.orig
[DROP] Debug_Level=TRACE
[KEEP] API_Key=xyz123abc
[KEEP] API_Endpoint=https://api.example.com/v1
[DROP] Old_API_Endpoint=http://api.example.com/v0
EOF

cat << 'EOF' > fileC.orig
[KEEP] Project_Name=SuperNova
[KEEP] Project_Version=1.0.4
[DROP] Build_Date=2021-09-01
EOF

for f in *.orig; do
    base=$(basename $f .orig)
    rev $f | base64 > ${base}.txt.cst
done

tar -czf /home/user/project_dump.tar.gz *.txt.cst
cd /home/user
rm -rf /home/user/dump_source

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
