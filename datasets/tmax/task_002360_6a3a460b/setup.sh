#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils
pip3 install pytest

mkdir -p /home/user/backups
mkdir -p /home/user/processing

cat << 'EOF' > /home/user/backups/app1.log
[START_RECORD]
Server: WEB_01
Timestamp: 1682820191
Event: LoginFailed
ErrorCode: 401
[END_RECORD]
[START_RECORD]
Server: WEB_02
Timestamp: 1682820195
Event: UserCreated
[END_RECORD]
[START_RECORD]
Server: DEPRECATED_SRV
Timestamp: 1682820199
Event: SystemHalt
ErrorCode: 500
[END_RECORD]
EOF

cat << 'EOF' > /home/user/backups/app2.log
[START_RECORD]
Server: DEPRECATED_SRV
Timestamp: 1682820200
Event: CoreDump
[END_RECORD]
[START_RECORD]
Server: DB_01
Timestamp: 1682820205
Event: QueryTimeout
[END_RECORD]
EOF

cd /home/user/backups
tar -czf raw_logs.tar.gz app1.log app2.log
rm app1.log app2.log

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
