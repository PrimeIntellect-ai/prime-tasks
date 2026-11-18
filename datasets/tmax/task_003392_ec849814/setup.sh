#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc tar coreutils
    pip3 install pytest

    mkdir -p /home/user/legacy_docs /home/user/current_docs /home/user/legacy_split /home/user/final_archive
    cd /home/user

    # Create legacy docs
    cat << 'EOF' > legacy_docs/draft_api.md
# API Documentation
Version 1.0. This is the legacy API documentation.
EOF

    cat << 'EOF' > legacy_docs/draft_intro.md
# Introduction
Welcome to the system.
EOF

    cat << 'EOF' > legacy_docs/draft_setup.md
# Setup
Run make install.
EOF

    # Package and split legacy docs
    tar -czf docs.tar.gz legacy_docs/
    split -b 150 docs.tar.gz /home/user/legacy_split/docs.tar.gz.part_
    rm -rf legacy_docs docs.tar.gz

    # Create current docs
    # draft_api.md is UNCHANGED
    cat << 'EOF' > current_docs/draft_api.md
# API Documentation
Version 1.0. This is the legacy API documentation.
EOF

    # draft_intro.md is MODIFIED
    cat << 'EOF' > current_docs/draft_intro.md
# Introduction
Welcome to the system. Updated for v2.0.
EOF

    # draft_faq.md is NEW
    cat << 'EOF' > current_docs/draft_faq.md
# FAQ
Q: How do I start?
A: Read the intro.
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/legacy_split /home/user/current_docs /home/user/final_archive
    chmod -R 777 /home/user
