#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/docs.jsonl
{"doc_id": "d1", "keywords": ["neural", "transformers", "networks", "gpt", "zero-trust", "python"]}
{"doc_id": "d2", "keywords": ["firewall", "encryption", "zero-trust", "rsa", "cloud", "networks"]}
{"doc_id": "d3", "keywords": ["aws", "azure", "cloud", "serverless", "docker", "networks", "firewall"]}
{"doc_id": "d4", "keywords": ["docker", "kubernetes", "cicd", "git", "python", "agile"]}
{"doc_id": "d5", "keywords": ["sql", "etl", "python", "pipeline", "cloud"]}
{"doc_id": "d6", "keywords": ["encryption", "botnet", "malware", "firewall"]}
EOF

    cat << 'EOF' > /home/user/data/mapping.csv
doc_id,category
d1,AI
d2,Cybersecurity
d3,Cloud
d4,DevOps
d5,DataOps
d6,Cybersecurity
EOF

    chmod -R 777 /home/user
