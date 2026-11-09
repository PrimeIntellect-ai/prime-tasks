#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/metadata.csv
doc_id,category,date
DOC_1,science,2023-01-01
DOC_2,history,2023-01-02
DOC_3,art,2023-01-03
DOC_5,tech,2023-01-05
EOF

    cat << 'EOF' > /home/user/data/texts.jsonl
{"id": 1, "content": "The quick brown fox jumps over 2 lazy dogs!"}
{"id": 2, "content": "History is written by the victors."}
{"id": 4, "content": "This should be ignored."}
{"id": 3, "content": "Art is in the eye of the beholder..."}
EOF

    chmod -R 777 /home/user
