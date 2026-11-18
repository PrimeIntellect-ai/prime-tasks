#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/docs.csv
doc_id,text
1,The quick brown fox jumps over the lazy dog!
2,Machine learning is fascinating. Learning is fun.
3,This is a test document. It is only a test.
invalid_id,Should be dropped.
5,Apples, oranges, and bananas are fruits.
6,The dog barked at the fox. The fox ran away.
EOF

    cat << 'EOF' > /home/user/data/meta.csv
doc_id,category,date
1,news,2023-01-01
2,blog,2023-01-02
3,wiki,2023-01-03
invalid_id,news,2023-01-04
5,invalid_category,2023-01-05
6,news,2023-01-06
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
