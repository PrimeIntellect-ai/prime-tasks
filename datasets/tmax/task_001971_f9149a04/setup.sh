#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
2023-10-01T14:32:01Z | ERROR | Process failed. Client IP: 192.168.1.50, Time taken: 120ms, ErrorCode: E404
2023-10-01T14:32:02Z | WARN | Timeout occurred. Client IP: 10.0.0.5, Time taken: 300ms, ErrorCode: E504
2023-10-01T14:32:03Z | ERROR | Process failed. Client IP: 192.168.1.50, Time taken: 120ms, ErrorCode: E404
2023-10-01T14:32:04Z | ERROR | Bad data. Client IP: 999.999.999.9999, Time taken: 50ms, ErrorCode: E400
2023-10-01T14:32:05Z | ERROR | Corrupted state. Client IP: 172.16.0.1, Time taken: -10ms, ErrorCode: E500
2023-10-01T14:32:06Z | INFO | System check. Client IP: 192.168.1.100, Time taken: 45ms, ErrorCode: E200
2023-10-01T14:32:07Z | WARN | Timeout occurred. Client IP: 10.0.0.5, Time taken: 310ms, ErrorCode: E504
2023-10-01T14:32:08Z | ERROR | Process failed. Client IP: 192.168.1.50, Time taken: 120ms, ErrorCode: E404
2023-10-01T14:32:09Z | INFO | Irrelevant log entry without specific patterns
EOF

    chmod -R 777 /home/user
