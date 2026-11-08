#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/raw_docs
    mkdir -p /home/user/processed_docs

    cat << 'EOF' > /home/user/raw_docs/draft_001_intro.txt
Title: Introduction
Author: Alice
Date: 2023-01-01

Welcome to the documentation.
EOF

    cat << 'EOF' > /home/user/raw_docs/draft_002_api.txt
Title: API Reference
Author: Bob
Date: 2023-01-02

Here is the API.
EOF

    cat << 'EOF' > /home/user/raw_docs/draft_003_storage.txt
Title: Storage Guide
Author: Charlie
Date: 2023-01-03

Data storage concepts.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
