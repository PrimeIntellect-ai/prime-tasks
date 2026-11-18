#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/base
    mkdir -p /home/user/data/inc

    # Create files in base
    echo -n "abc" > /home/user/data/base/file1.txt
    echo -n "defg" > /home/user/data/base/file2.txt
    echo -n "hi" > /home/user/data/base/file3.txt
    echo -n "jklmnop" > /home/user/data/base/file5.txt

    # Create files in inc
    echo -n "abc" > /home/user/data/inc/file1.txt
    echo -n "defg_changed" > /home/user/data/inc/file2.txt
    echo -n "xyz" > /home/user/data/inc/file4.txt
    echo -n "jklmnop" > /home/user/data/inc/file5.txt

    # Create JSON config
    cat << 'EOF' > /home/user/backups.json
{
  "system": "prod",
  "directories": {
    "base": "/home/user/data/base",
    "inc": "/home/user/data/inc"
  }
}
EOF

    # Create multi-line log
    cat << 'EOF' > /home/user/sync.log
FILE: file1.txt
SIZE: 3
STATUS: SUCCESS
FILE: file2.txt
SIZE: 12
STATUS: SUCCESS
FILE: file3.txt
SIZE: 2
STATUS: FAILED
FILE: file4.txt
SIZE: 3
STATUS: SUCCESS
FILE: file5.txt
SIZE: 7
STATUS: SUCCESS
EOF

    chown -R user:user /home/user/data /home/user/backups.json /home/user/sync.log
    chmod -R 777 /home/user
