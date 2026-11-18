#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/etl_translation_logs.txt
2023-10-25T09:50:00Z | Task:A0 | Target:fr-FR | Latency:50ms
10/25/2023 10:01:00 | Task:A2 | Target:fr-FR | Latency:150ms
2023-10-25T10:00:00Z | Task:A1 | Target:fr-FR | Latency:200ms
2023-10-25T10:02:00Z | Task:A3 | Target:fr-FR | Latency:100ms
2023-10-25T10:05:00Z | Task:A1 | Target:fr-FR | Latency:210ms
2023-10-25T10:06:00Z | Task:A4 | Target:es-ES | Latency:300ms
Error: connection timeout on Task:A2 - retrying
10/25/2023 10:07:00 | Task:A5 | Target:fr-FR | Latency:300ms
EOF

    chmod -R 777 /home/user
