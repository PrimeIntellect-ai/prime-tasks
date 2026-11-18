#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/survey.csv
id,group,text
1,A,hello world
2,A,this is a test
3,,missing group text
4,B,one two three
5,B,just one
6,A,outlier text that goes on and on and on and on and on and on and on and on and on and on and on
7,B,another valid text for b
8,A,valid a
9,B,singleword
10,C,wrong group
11,A,one more valid a text
EOF

    chmod -R 777 /home/user
