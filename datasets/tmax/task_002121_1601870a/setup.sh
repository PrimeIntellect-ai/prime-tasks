#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/spool
    mkdir -p /home/user/staging
    mkdir -p /home/user/vault

    cat << 'EOF' > /home/user/test_batch.map
file1.txt:reports/file1.txt
file2.txt:reports/../images/file2.txt
evil1.txt:../../user/evil1.txt
file3.txt:deep/nested/path/file3.txt
evil2.txt:/etc/passwd_copy
EOF

    echo -n "1" > /home/user/staging/file1.txt
    echo -n "2" > /home/user/staging/file2.txt
    echo -n "evil" > /home/user/staging/evil1.txt
    echo -n "3" > /home/user/staging/file3.txt
    echo -n "evil" > /home/user/staging/evil2.txt

    chmod -R 777 /home/user
