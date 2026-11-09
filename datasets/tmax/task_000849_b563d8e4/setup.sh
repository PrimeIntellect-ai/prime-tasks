#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/categories.csv
id,parent_id,name
1,,Computer Science
2,,Biology
3,1,Artificial Intelligence
4,3,Machine Learning
5,1,Databases
6,2,Genetics
7,2,Botany
8,6,Epigenetics
9,,Physics
10,9,Quantum Mechanics
EOF

    cat << 'EOF' > /home/user/papers.jsonl
{"id": "p1", "category_id": 4, "citations": 120}
{"id": "p2", "category_id": 5, "citations": 45}
{"id": "p3", "category_id": 8, "citations": 300}
{"id": "p4", "category_id": 2, "citations": 15}
{"id": "p5", "category_id": 1, "citations": 10}
{"id": "p6", "category_id": 10, "citations": 85}
{"id": "p7", "category_id": 7, "citations": 22}
{"id": "p8", "category_id": 3, "citations": 70}
EOF

    cat << 'EOF' > /home/user/expected_report.txt
Biology: 337
Computer Science: 245
Physics: 85
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
