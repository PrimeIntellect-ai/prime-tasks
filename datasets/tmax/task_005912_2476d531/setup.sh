#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/authors.csv
author_id,name,institution_id
1,Alice,INST_A
2,Bob,INST_B
3,Charlie,INST_A
4,David,INST_C
5,Eve,INST_B
6,Frank,INST_D
EOF

    cat << 'EOF' > /home/user/data/papers.json
[
  {"paper_id": 101, "title": "AI Systems", "author_ids": [1, 2]},
  {"paper_id": 102, "title": "Data Mining", "author_ids": [3]},
  {"paper_id": 103, "title": "Graph DBs", "author_ids": [4, 5]},
  {"paper_id": 104, "title": "NLP Trends", "author_ids": [6]},
  {"paper_id": 105, "title": "Quantum ML", "author_ids": [2]}
]
EOF

    cat << 'EOF' > /home/user/data/citations.csv
citing_paper_id,cited_paper_id
101,102
101,104
103,101
103,105
105,103
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
