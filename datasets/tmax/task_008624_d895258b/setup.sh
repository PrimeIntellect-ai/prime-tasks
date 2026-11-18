#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/papers.json
[
  {"paper_id": "P01", "title": "Graph Theory Fundamentals", "authors": ["Alice"]},
  {"paper_id": "P02", "title": "Advanced PageRank", "authors": ["Bob"]},
  {"paper_id": "P03", "title": "Clustering Dynamics", "authors": ["Charlie"]},
  {"paper_id": "P04", "title": "Network Science", "authors": ["Dave"]},
  {"paper_id": "P05", "title": "Algorithms 101", "authors": ["Eve"]},
  {"paper_id": "P06", "title": "Data Structures", "authors": ["Frank"]},
  {"paper_id": "P07", "title": "Social Networks", "authors": ["Grace"]},
  {"paper_id": "P08", "title": "Community Detection", "authors": ["Heidi"]},
  {"paper_id": "P09", "title": "Matrix Computations", "authors": ["Ivan"]},
  {"paper_id": "P10", "title": "Isolated Research", "authors": ["Judy"]}
]
EOF

    cat << 'EOF' > /home/user/data/citations.csv
source_id,target_id
P02,P01
P03,P01
P04,P01
P05,P02
P06,P02
P07,P08
P09,P08
P10,P08
P10,P09
P09,P07
P07,P10
P06,P05
P05,P06
EOF

    chmod -R 777 /home/user
