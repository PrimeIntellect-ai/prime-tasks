#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/weights.tsv
0.5	1.2
EOF

    cat << 'EOF' > /home/user/raw_data.jsonl
{"id": 1, "text": "short text", "summary": "short"}
{"id": 2, "text": "This is a sufficiently long text to pass the threshold.", "summary": "A good summary."}
{"id": "3", "text": "Invalid id type", "summary": "drop"}
{"id": 4, "text": "Another perfectly fine text that should definitely be included in the output.", "summary": "Included."}
{"id": 5, "text": "This is a sufficiently long text to pass the threshold.", "summary": "Duplicate text."}
{"id": 6, "text": "Valid text but missing summary"}
{"id": 7, "text": "Extremely long text that goes on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on.", "summary": "Way too long."}
{"id": 8, "text": "A valid row", "summary": "Valid row summary.", "extra": "field"}
{"id": 9, "text": "Final valid text for the test case.", "summary": "Final summary."}
EOF

    chmod -R 777 /home/user
