#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/db_dump.jsonl
{"tx_id": "T1", "parties": ["A", "B"], "time_start": 10, "time_end": 20}
{"id": "T2", "source": "A", "target": "C", "start": 15, "end": 25}
{"transactionId": "T3", "acc": "B", "t0": 18, "t1": 30}
{"tx_id": "T4", "parties": ["C", "D"], "time_start": 10, "time_end": 12}
{"id": "T5", "source": "B", "target": "E", "start": 25, "end": 35}
{"transactionId": "T6", "acc": "E", "t0": 28, "t1": 40}
{"tx_id": "T7", "parties": ["A", "F"], "time_start": 19, "time_end": 22}
{"id": "T8", "source": "F", "target": "G", "start": 21, "end": 29}
{"transactionId": "T9", "acc": "G", "t0": 25, "t1": 27}
EOF

    chmod -R 777 /home/user
