#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential tar gzip
    pip3 install pytest

    mkdir -p /home/user/user_data/alice
    mkdir -p /home/user/user_data/bob
    mkdir -p /home/user/user_data/charlie
    mkdir -p /home/user/backups

    echo "hello alice" > /home/user/user_data/alice/file.txt
    echo "hello bob" > /home/user/user_data/bob/file.txt
    echo "hello charlie" > /home/user/user_data/charlie/file.txt

    cat <<EOF > /home/user/quota_data.txt
alice:450:500
bob:600:500
charlie:500:500
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
