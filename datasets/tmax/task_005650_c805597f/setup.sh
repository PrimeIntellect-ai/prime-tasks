#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/metadata.csv
paper_id,year,author
P001,2020,Smith
P002,2022,Jones
P003,2022,Lee
P004,2021,Wong
P005,2022,Gupta
P006,2022,Kim
P007,2022,Chen
EOF

    cat << 'EOF' > /home/user/citations.txt
P002 P001
P003 P001
P004 P001
P005 P001
P006 P002
P007 P001
EOF

    cat << 'EOF' > /home/user/documents.json
[
  {"paper_id": "P001", "keywords": ["Foundations"]},
  {"paper_id": "P002", "keywords": ["NLP", "Transformers"]},
  {"paper_id": "P003", "keywords": ["Graph", "NLP"]},
  {"paper_id": "P004", "keywords": ["Vision"]},
  {"paper_id": "P005", "keywords": ["NLP", "Ethics", "Graph"]},
  {"paper_id": "P006", "keywords": ["Robotics"]},
  {"paper_id": "P007", "keywords": ["Graph", "Transformers"]}
]
EOF

    chmod -R 777 /home/user
