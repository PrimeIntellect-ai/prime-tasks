#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils sed
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_translations.jsonl
{"lang": "es-ES", "seq_id": 1, "translator": "ana@test.com", "text": "Hola\\u0021"}
{"lang": "es-ES", "seq_id": 2, "translator": "ana@test.com", "text": "Adi\\u00f3s"}
{"lang": "es-ES", "seq_id": 4, "translator": "luis@test.com", "text": "Ma\\u00f1ana"}
{"lang": "de-DE", "seq_id": 10, "translator": "hans@test.com", "text": "Guten Tag\\u0021"}
{"lang": "de-DE", "seq_id": 13, "translator": "hans@test.com", "text": "Tsch\\u00fcss"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
