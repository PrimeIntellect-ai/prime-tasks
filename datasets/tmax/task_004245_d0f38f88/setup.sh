#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/app
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/logs/frontend.log
[03:00:00] Forwarding REQ-001
[03:00:01] Completed REQ-001
[03:00:02] Forwarding REQ-002
[03:00:03] Completed REQ-002
[03:00:04] Forwarding REQ-003
[03:00:05] Connection lost to backend for REQ-003
[03:00:06] Forwarding REQ-004
[03:00:07] Completed REQ-004
[03:00:08] Forwarding REQ-005
[03:00:09] Connection lost to backend for REQ-005
[03:00:10] Forwarding REQ-006
[03:00:11] Completed REQ-006
[03:00:12] Forwarding REQ-008
[03:00:13] Connection lost to backend for REQ-008
EOF

    cat << 'EOF' > /home/user/logs/backend.log
[03:00:00] Processing REQ-001
[03:00:01] Success REQ-001
[03:00:02] Processing REQ-002
[03:00:03] Success REQ-002
[03:00:04] Processing REQ-003
[03:00:05] FATAL ERROR: ValueError
[03:00:06] Processing REQ-004
[03:00:07] Success REQ-004
[03:00:08] Processing REQ-005
[03:00:09] FATAL ERROR: TypeError
[03:00:10] Processing REQ-006
[03:00:11] Success REQ-006
[03:00:12] Processing REQ-008
[03:00:13] FATAL ERROR: LinAlgError
EOF

    cat << 'EOF' > /home/user/data/payload.jsonl
{"id": "REQ-001", "matrix": [[1, 2], [3, 4]]}
{"id": "REQ-002", "matrix": [[2, 0], [0, 2]]}
{"id": "REQ-003", "matrix": [[1, 2], ["a", "b"]]}
{"id": "REQ-004", "matrix": [[5, 1], [1, 5]]}
{"id": "REQ-005", "matrix": "corrupted"}
{"id": "REQ-006", "matrix": [[1, 0, 0], [0, 1, 0], [0, 0, 1]]}
{"id": "REQ-008", "matrix": [[1, 2, 3], [4, 5, 6]]}
EOF

    cat << 'EOF' > /home/user/app/requirements.txt
numpy
EOF

    cat << 'EOF' > /home/user/app/backend.py
import json
import numpy as np

def process_file():
    total_det = 0.0
    with open('/home/user/data/payload.jsonl', 'r') as f:
        for line in f:
            data = json.loads(line)
            req_id = data['id']
            mat = np.array(data['matrix'], dtype=float)
            det = np.linalg.det(mat)
            total_det += det

    with open('/home/user/result.txt', 'w') as out:
        out.write(str(total_det))

if __name__ == "__main__":
    process_file()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
