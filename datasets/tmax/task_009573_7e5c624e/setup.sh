#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/dataset
    cat << 'EOF' > /home/user/dataset/authors.csv
author_id,name
1,Alice
2,Bob
3,Charlie
4,Diana
5,Eve
6,Frank
7,Grace
EOF

    cat << 'EOF' > /home/user/dataset/paper_authors.csv
paper_id,author_id
101,1
101,2
101,3
102,1
102,4
102,5
103,2
103,6
104,3
104,6
105,1
105,6
106,7
106,1
106,4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
