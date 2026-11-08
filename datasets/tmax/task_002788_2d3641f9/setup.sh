#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/docs

    cat << 'EOF' > /home/user/docs/intro.md
---
title: Introduction
status: published
---
Welcome to the LegacyBrand documentation.
LegacyBrand provides top-tier solutions.
EOF

    cat << 'EOF' > /home/user/docs/draft_api.md
---
title: API Reference
status: draft
---
The LegacyBrand API is currently under construction.
Please check back later for LegacyBrand updates.
EOF

    cat << 'EOF' > /home/user/docs/setup.md
---
title: Setup Guide
status: published
---
To install LegacyBrand, run the installer.
Thank you for choosing LegacyBrand.
EOF

    cat << 'EOF' > /home/user/docs/notes.txt
status: published
These are some personal notes about LegacyBrand.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
