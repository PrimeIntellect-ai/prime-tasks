#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo build-essential libjson-c-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/user
    chmod 0440 /etc/sudoers.d/user

    mkdir -p /home/user/dataset
    mkdir -p /home/user/workspace
    mkdir -p /home/user/results

    cat << 'EOF' > /home/user/dataset/papers.json
[
  {"paper_id": 1, "title": "Intro to Graphs", "year": 2020},
  {"paper_id": 2, "title": "Advanced Trees", "year": 2021},
  {"paper_id": 3, "title": "Centrality Metrics", "year": 2021},
  {"paper_id": 4, "title": "Clustering", "year": 2022},
  {"paper_id": 5, "title": "Network Dynamics", "year": 2023}
]
EOF

    cat << 'EOF' > /home/user/dataset/authors.csv
paper_id,author_name
1,Alice
1,Bob
1,Charlie
2,Bob
2,David
3,Alice
3,Eve
4,Charlie
4,Eve
5,Alice
5,Bob
5,Charlie
5,Eve
EOF

    chown -R user:user /home/user/dataset /home/user/workspace /home/user/results
    chmod -R 777 /home/user
