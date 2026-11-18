#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow fastparquet

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/batch1.jsonl
{"user_id": 1, "name": "Alice", "email": "alice@example.com", "phone": "123-456-7890", "timestamp": "2023-10-01T10:00:00Z"}
{"user_id": 2, "name": "Bob", "email": "bob@test.com", "phone": "555-000-1111", "timestamp": "2023-10-01T10:05:00Z"}
EOF

    cat << 'EOF' > /home/user/data/batch2.csv
user_id,name,email,phone,timestamp
2,Bob,bob@test.com,555-000-1111,2023-10-01T10:05:00Z
3,Charlie,charlie@domain.org,999-888-7777,2023-10-01T10:10:00Z
EOF

    cat << 'EOF' > /home/user/data/batch3_retry.jsonl
{"user_id": 2, "name": "Bob Updated", "email": "bob.new@test.com", "phone": "555-000-2222", "timestamp": "2023-10-01T10:15:00Z"}
{"user_id": 4, "name": "Diana", "email": "diana@company.net", "phone": "11", "timestamp": "2023-10-01T10:20:00Z"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
