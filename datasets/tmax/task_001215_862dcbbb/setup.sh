#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/docs_system/drafts
    mkdir -p /home/user/docs_system/chunks

    cat << 'EOF' > /home/user/docs_system/drafts/docA.md
Title: Doc A
Status: Draft
Contents containing [SECRET] data.
More text here.
EOF

    cat << 'EOF' > /home/user/docs_system/drafts/docB.md
Title: Doc B
Status: Review
This one has no secrets.
EOF

    cat << 'EOF' > /home/user/docs_system/drafts/docC.md
Title: Doc C
Status: Draft
Another [SECRET] mission.
[SECRET] is everywhere.
EOF

    cat << 'EOF' > /home/user/docs_system/monolith.md
Chapter 1
Hellooo
---SPLIT---
Chapter 2
Spacesss   !
---SPLIT---
Chapter 3
AABBCC
EOF

    chmod -R 777 /home/user
