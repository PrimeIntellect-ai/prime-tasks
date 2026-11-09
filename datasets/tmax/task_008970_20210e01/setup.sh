#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/remote_archive
    mkdir -p /home/user/workspace/data
    mkdir -p /home/user/workspace/processed

    cat << 'EOF' > /home/user/remote_archive/log_A.jsonl
{"timestamp": "2023-11-01T00:00:00Z", "size_bytes": 1000, "message": "Start \u0001"}
{"timestamp": "2023-11-01T03:00:00Z", "size_bytes": 1300, "message": "Bad unicode \u12XZ here"}
{"timestamp": "2023-11-01T04:00:00Z", "size_bytes": 1400, "message": "Ok"}
EOF

    cat << 'EOF' > /home/user/remote_archive/log_B.jsonl
{"timestamp": "2023-11-02T00:00:00Z", "size_bytes": 2000, "message": "Valid"}
{"timestamp": "2023-11-02T02:00:00Z", "size_bytes": 2500, "message": "Broken \uZZZZ"}
EOF

    cat << 'EOF' > /home/user/remote_archive/log_C.jsonl
{"timestamp": "2023-11-03T10:00:00Z", "size_bytes": 5000, "message": "End"}
{"timestamp": "2023-11-03T12:00:00Z", "size_bytes": 5100, "message": "Really broken \u00"}
EOF

    chmod -R 777 /home/user
