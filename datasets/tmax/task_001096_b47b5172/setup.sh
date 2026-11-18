#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_data.csv
id,text
1,The quick brown fox.
2,The fast brown fox!
3,A quick red fox?
4,Data science is extremely fun.
5,Data science is extremely fun today!
6,Machine learning is cool.
7,Artificial intelligence is cool.
8,I love to write code!
9,I really love to write code.
10,The quick brown dog.
EOF

    chmod -R 777 /home/user
