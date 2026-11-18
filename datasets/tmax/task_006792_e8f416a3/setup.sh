#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/scraped_data.jsonl
{"id": 1, "body": "This is the first document. It is perfectly valid.", "meta": "A"}
{"id": 2, "body": "This document has a bad unicode escape \uZZZZ.", "meta": "B"}
{"id": 3, "body": "This is the first document. It is perfectly valid.", "meta": "C"}
{"id": 4, "body": "A unique document here.", "meta": "D"}
{"id": 5, "body": "Another unique document.", "meta": "E"}
{"id": 6, "body": "A unique document here.", "meta": "F"}
{"id": 7, "body": "Broken json missing closing brace", "meta": "G"
{"id": 8, "body": "Final valid unique document.", "meta": "H"}
EOF

    chmod -R 777 /home/user
