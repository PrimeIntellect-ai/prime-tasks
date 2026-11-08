#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bzip2
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/safe_zone

    cat << 'EOF' > /home/user/admin.conf
USER_ID=storage_admin
REDACT_PATTERN=[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}
SPLIT_LINES=5
MAX_STORAGE=100G
EOF

    mkdir -p /tmp/log_builder/deep/nested/dir
    mkdir -p /tmp/log_builder/dangerous

    cat << 'EOF' > /tmp/log_builder/deep/nested/dir/access.log
User login from 192.168.1.100
Failed attempt from 10.0.0.5
Success from 127.0.0.1
System check complete.
EOF

    cat << 'EOF' > /tmp/log_builder/server.log
Line 1: 192.168.1.1
Line 2: data
Line 3: data
Line 4: 10.10.10.10
Line 5: data
Line 6: data
Line 7: 172.16.0.1
Line 8: end
EOF

    cat << 'EOF' > /tmp/log_builder/data.csv
id,name,ip
1,alice,192.168.1.50
2,bob,10.0.0.200
3,charlie,172.16.5.5
EOF

    python3 -c "
import tarfile
with tarfile.open('/home/user/incoming/logs.tar.gz', 'w:gz') as tar:
    tar.add('/tmp/log_builder/deep/nested/dir/access.log', arcname='deep/nested/dir/access.log')
    tar.add('/tmp/log_builder/server.log', arcname='server.log')
    tar.add('/tmp/log_builder/data.csv', arcname='../../home/user/data.csv')
"

    rm -rf /tmp/log_builder

    chown -R user:user /home/user/
    chmod -R 777 /home/user
