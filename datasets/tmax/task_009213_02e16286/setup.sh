#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/results

    cat << 'EOF' > /home/user/data/abstracts.csv
id,text
101,"Machine learning for data science!"
102,"Deep learning models are large."
103,"Cell biology and genetics."
104,"Data science and biology."
EOF

    cat << 'EOF' > /home/user/data/metadata.jsonl
{"id": 101, "prior": 0.5}
{"id": 102, "prior": 0.8}
{"id": 103, "prior": 0.1}
{"id": 104, "prior": 0.4}
EOF

    cat << 'EOF' > /home/user/data/likelihoods.json
{
  "machine": {"1": 0.8, "0": 0.01},
  "learning": {"1": 0.9, "0": 0.05},
  "data": {"1": 0.7, "0": 0.1},
  "science": {"1": 0.6, "0": 0.2},
  "biology": {"1": 0.05, "0": 0.9},
  "genetics": {"1": 0.01, "0": 0.95},
  "models": {"1": 0.7, "0": 0.2}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
