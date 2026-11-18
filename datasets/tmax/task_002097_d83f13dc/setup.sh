#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip file tar gzip zip unzip jq
    pip3 install pytest

    mkdir -p /home/user/workspace/raw/subdir
    mkdir -p /home/user/workspace/extracted
    mkdir -p /home/user/workspace/binaries

    cat << 'EOF' > /home/user/workspace/raw/metadata.json
{
  "project_name": "LegacySystem",
  "project_version": "2.9.4-beta",
  "author": "dev_team"
}
EOF

    python3 -c 'open("/home/user/workspace/raw/subdir/data.csv", "wb").write(b"id,name\n1,Caf\xe9\n2,R\xe9sum\xe9\n")'

    cp /bin/ls /home/user/workspace/raw/ls_bin
    cp /bin/pwd /home/user/workspace/raw/subdir/pwd_bin

    echo "Regular text file" > /home/user/workspace/raw/readme.txt

    cd /home/user/workspace/raw
    tar -czf /home/user/workspace/incoming.tar.gz ./*

    rm -rf /home/user/workspace/raw

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
