#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/authors.jsonl
{"author_id": "A1", "name": "Alice Adams"}
{"author_id": "A2", "name": "Bob Baker"}
{"author_id": "A3", "name": "Charlie Clark"}
{"author_id": "A4", "name": "Diana Doe"}
{"author_id": "A5", "name": "Evan Evans"}
{"author_id": "A6", "name": "Fiona Fox"}
EOF

    cat << 'EOF' > /home/user/papers.csv
paper_id,title,author_id
P1,Title 1,A1
P2,Title 2,A2
P3,Title 3,A3
P4,Title 4,A4
P5,Title 5,A5
P6,Title 6,A6
EOF

    cat << 'EOF' > /home/user/citations.txt
P1 -> P2
P2 -> P3
P3 -> P1
P4 -> P5
P5 -> P6
P6 -> P4
P1 -> P4
P3 -> P6
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
