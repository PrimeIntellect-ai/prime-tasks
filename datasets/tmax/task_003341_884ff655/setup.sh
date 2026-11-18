#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/reviews.csv
review_id,user_id,submitted_at,review_text
R001,U101,2023-10-01 12:00:00,"This is a great product.
I loved it!"
R002,U102,2023-10-01 12:05:30,"Terrible experience.
Will never buy again.
Ever."
R003,U103,2023-10-01 12:10:15,"Okay product, nothing special."
R004,U104,2023-10-01 12:15:00,"Amazing!
Five stars!

Highly recommend."
EOF

    cat << 'EOF' > /home/user/data/server_logs.jsonl
{"review_id": "R001", "ingest_epoch": 1696161605, "server_ip": "192.168.1.10"}
{"review_id": "R002", "ingest_epoch": 1696161945, "server_ip": "192.168.1.11"}
{"review_id": "R003", "ingest_epoch": 1696162215, "server_ip": "192.168.1.10"}
{"review_id": "R004", "ingest_epoch": 1696162502, "server_ip": "192.168.1.12"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
