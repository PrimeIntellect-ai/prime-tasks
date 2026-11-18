#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/data/configs/

    cat << 'EOF' > /home/user/data/metadata.csv
server_id,owner_email,department
srv1,alice@example.com,IT
srv2,bob@example.com,Engineering
srv3,charlie@example.com,Finance
EOF

    cat << 'EOF' > /home/user/data/configs/config_2023-10-01.jsonl
{"server_id": "srv1", "date": "2023-10-01", "packages": ["A", "B", "C\uZZZZ"]}
{"server_id": "srv2", "date": "2023-10-01", "packages": ["X", "Y"]}
{"server_id": "srv3", "date": "2023-10-01", "packages": ["M", "N", "O"]}
EOF

    cat << 'EOF' > /home/user/data/configs/config_2023-10-02.jsonl
{"server_id": "srv1", "date": "2023-10-02", "packages": ["A", "B", "C", "D"]}
{"server_id": "srv2", "date": "2023-10-02", "packages": ["X", "Y"]}
{"server_id": "srv3", "date": "2023-10-02", "packages": ["M", "N", "O", "P"]}
EOF

    cat << 'EOF' > /home/user/data/configs/config_2023-10-03.jsonl
{"server_id": "srv1", "date": "2023-10-03", "packages": ["A", "B", "D"]}
{"server_id": "srv2", "date": "2023-10-03", "packages": ["X", "Y"]}
{"server_id": "srv3", "date": "2023-10-03", "packages": ["M", "N", "P"]}
EOF

    cat << 'EOF' > /home/user/data/configs/config_2023-10-04.jsonl
{"server_id": "srv1", "date": "2023-10-04", "packages": ["A", "D\uWWWW"]}
{"server_id": "srv2", "date": "2023-10-04", "packages": ["X", "Y"]}
{"server_id": "srv3", "date": "2023-10-04", "packages": ["M", "P"]}
EOF

    cat << 'EOF' > /home/user/data/configs/config_2023-10-05.jsonl
{"server_id": "srv1", "date": "2023-10-05", "packages": ["A"]}
{"server_id": "srv2", "date": "2023-10-05", "packages": ["X", "Y\uQQQQ"]}
{"server_id": "srv3", "date": "2023-10-05", "packages": ["M", "P"]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
