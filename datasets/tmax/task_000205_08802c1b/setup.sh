#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.tsv
1	Science	Hello World! This is a test.
A	Math	Invalid ID here
2	Math	C++ is extremely fast!
3	Physics	Quantum mechanics is fascinating.
4		Missing category string
5	History	1914 WW1 started.
6	Bi0logy	Invalid category name
7	CS	Code
8	Art	The Mona Lisa is a half-length portrait painting.
EOF

    cat << 'EOF' > /home/user/queries.tsv
101	Science	Hello World testing.
102	CS	C++ programming is quick.
103	Physics	Quantum theory rules!
B	Art	Invalid query
EOF

    chmod -R 777 /home/user
