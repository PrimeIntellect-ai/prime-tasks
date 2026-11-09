#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/metadata.csv
id,name
1,Alice
2,Bob
EOF

    cat << 'EOF' > /home/user/research_data.jsonl
{"id": 101, "researcher_id": 1, "data": "Result A"}
{"id": 102, "researcher_id": 2, "data": "Result B"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
