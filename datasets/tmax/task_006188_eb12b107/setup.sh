#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user/dataset

    cat << 'EOF' > /home/user/dataset/p1.json
{
  "id": "P1",
  "title": "Introduction to Graph DBs",
  "institution": "InstA",
  "citations": ["P2", "P3"]
}
EOF

    cat << 'EOF' > /home/user/dataset/p2.json
{
  "id": "P2",
  "title": "Advanced NoSQL Aggregation",
  "institution": "InstB",
  "citations": ["P3", "P4"]
}
EOF

    cat << 'EOF' > /home/user/dataset/p3.json
{
  "id": "P3",
  "title": "Cross-Representation Mapping",
  "institution": "InstC",
  "citations": ["P4"]
}
EOF

    cat << 'EOF' > /home/user/dataset/p4.json
{
  "id": "P4",
  "title": "Query Pipeline Optimization",
  "institution": "InstA",
  "citations": ["P1", "P5"]
}
EOF

    cat << 'EOF' > /home/user/dataset/p5.json
{
  "id": "P5",
  "title": "Result Pagination Strategies",
  "institution": "InstB",
  "citations": ["P1"]
}
EOF

    cat << 'EOF' > /home/user/dataset/p6.json
{
  "id": "P6",
  "title": "Schema Analysis Frameworks",
  "institution": "InstC",
  "citations": ["P1", "P2"]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
