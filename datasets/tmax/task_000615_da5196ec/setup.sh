#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_docs
    mkdir -p /home/user/processed_docs

    cat << 'EOF' > /home/user/doc_rules.conf
SEARCH=LegacySys
REPLACE=QuantumFlow
DELIMITER=@@@PAGE_BREAK@@@
EOF

    cat << 'EOF' > /home/user/legacy_docs/user_manual.txt
Status: ReadyForArchive
Welcome to the LegacySys User Manual.
This system is the best LegacySys has to offer.
@@@PAGE_BREAK@@@
Chapter 2: Operation
To operate LegacySys, press the big red button.
@@@PAGE_BREAK@@@
Chapter 3: Maintenance
LegacySys requires daily oiling.
EOF

    cat << 'EOF' > /home/user/legacy_docs/draft_notes.txt
Status: Draft
This file should NOT be processed.
It mentions LegacySys but lacks the correct header.
@@@PAGE_BREAK@@@
More draft notes.
EOF

    cat << 'EOF' > /home/user/legacy_docs/api_guide.txt
Status: ReadyForArchive
LegacySys API Documentation
@@@PAGE_BREAK@@@
Endpoints:
GET /api/legacy
Returns LegacySys status.
EOF

    chown -R user:user /home/user/legacy_docs
    chown -R user:user /home/user/processed_docs
    chown user:user /home/user/doc_rules.conf

    chmod -R 777 /home/user
