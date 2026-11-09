#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/docs

    cat << 'EOF' > /home/user/docs/networking.md
---
Author: Jane Doe
Topic: Networking
---
# Networking Guide
This guide explains the network setup.
EOF

    cat << 'EOF' > /home/user/docs/api_v2.md
---
Author: John Smith
Topic: API
---
# API v2
API documentation.
EOF

    cat << 'EOF' > /home/user/docs/auth.md
---
Author: Alice Johnson
Topic: Security
---
# Authentication
Details on OAuth2.
EOF

    cat << 'EOF' > /home/user/docs/db_schema.md
---
Author: Bob tables
Topic: Database
---
# Database
Schema docs.
EOF

    cat << 'EOF' > /home/user/build_errors.log
[INFO] Starting build process at 2023-10-25 10:00:00
[INFO] Processing frontmatter...
[ERROR] Build interrupted.
File: /home/user/docs/auth.md
Reason: Invalid Markdown table syntax
[INFO] Attempting to continue...
[WARN] Skipping /home/user/docs/auth.md
[INFO] Processing assets...
[ERROR] Build interrupted.
File: /home/user/docs/api_v2.md
Reason: Unresolved reference to 'UserEndpoint'
[INFO] Build finished with errors.
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/docs
    chown user:user /home/user/build_errors.log
    chmod -R 777 /home/user
