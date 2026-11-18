#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/data.csv
id,text,engagement_score
1,Hello world of AI,0.9
2,This is a test!!,0.2
3,AI is the future of tech.,0.85
4,Short,0.1
5,Another long sentence without the magic word,0.4
6,Data science and AI go hand-in-hand,0.95
7,Just a random string of words for testing...,0.3
8,AI AI AI AI AI,0.99
9,Machine learning is cool!,0.7
10,I love programming in Go,0.6
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
