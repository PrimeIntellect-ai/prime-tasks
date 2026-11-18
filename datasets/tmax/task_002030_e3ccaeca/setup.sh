#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /home/user/docs_draft/
    mkdir -p /home/user/indexer/

    # Create the config file
    cat << 'EOF' > /home/user/doc_config.txt
s/TODO:\[\(.*\)\]/NOTE: \1/g
s/[DRAFT]//g
EOF

    # Create draft markdown files
    cat << 'EOF' > /home/user/docs_draft/intro.md
# Introduction to the System
This is a [DRAFT] document.
TODO:[Add architecture diagram]
EOF

    cat << 'EOF' > /home/user/docs_draft/setup.md
# Installation Guide
Follow these steps to install the system.
TODO:[Verify permissions on step 3]
EOF

    cat << 'EOF' > /home/user/docs_draft/api.md
# API Reference
[DRAFT] API Endpoints:
TODO:[Document the /users endpoint]
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/docs_draft/
    chown -R user:user /home/user/indexer/
    chown user:user /home/user/doc_config.txt
    chmod -R 777 /home/user
