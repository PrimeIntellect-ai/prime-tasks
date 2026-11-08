#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/input
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/input/data1.jsonl
{"ts": "2023-10-01T10:15:00Z", "id": "1", "text": "Hello", "lang": "en"}
{"ts": "2023-10-01T10:45:00Z", "id": "2", "text": "Hola", "lang": "es"}
{"ts": "2023-10-01T11:05:00Z", "id": "3", "text": "Bonjour", "lang": "fr"}
EOF

    cat << 'EOF' > /home/user/input/data2.jsonl
{"ts": "2023-10-01T10:50:00Z", "id": "2", "text": "Hola", "lang": "es"}
{"ts": "2023-10-01T11:20:00Z", "id": "4", "text": "こんにちは", "lang": "ja"}
{"ts": "2023-10-02T08:10:00Z", "id": "5", "text": "مرحبا", "lang": "ar"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
