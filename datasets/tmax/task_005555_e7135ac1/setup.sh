#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/updates.csv
timestamp,metric_id,value
10,1,5.0
12,1,7.0
15,2,10.0
EOF

    cat << 'EOF' > /home/user/updates.jsonl
{"ts": 11, "id": 2, "val": 4.0}
{"ts": 12, "id": 2, "val": 6.0}
{"ts": 14, "id": 1, "val": 3.0}
{"ts": 17, "id": 1, "val": 8.0}
EOF

    chmod -R 777 /home/user
