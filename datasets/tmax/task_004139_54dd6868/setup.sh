#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/src
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/vocab.txt
quick
brown
fox
lazy
dog
EOF

    cat << 'EOF' > /home/user/data/dataset.csv
id,text
1,the quick brown fox jumps over the lazy dog
2,a quick brown dog outpaces a fast fox
3,the lazy dog sleeps all day
4,fox quick brown
5,the dog is quick and brown
6,nothing matches here
EOF

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    chmod -R 777 /home/user
