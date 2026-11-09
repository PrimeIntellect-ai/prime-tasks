#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create required directories
    mkdir -p /home/user/docs_raw
    mkdir -p /home/user/stray_docs
    mkdir -p /home/user/tmp_archive

    # Create doc_build.conf
    cat << 'EOF' > /home/user/doc_build.conf
[User_Guide]
chunks = intro.txt, installation.txt, usage.txt
output = /home/user/final_docs/User_Guide.md

[API_Reference]
chunks = api_overview.txt, endpoints.txt
output = /home/user/final_docs/API_Reference.md
EOF

    # Create chunk files
    cat << 'EOF' > /home/user/docs_raw/intro.txt
[[H1]] Introduction
Welcome to the system.
EOF

    cat << 'EOF' > /home/user/stray_docs/installation.txt
[[H1]] Installation
[[H2]] Prerequisites
Need python.
EOF

    cat << 'EOF' > /home/user/tmp_archive/usage.txt
[[H1]] Usage
Run the script.
EOF

    cat << 'EOF' > /home/user/docs_raw/api_overview.txt
[[H1]] API Overview
RESTful API.
EOF

    cat << 'EOF' > /home/user/stray_docs/endpoints.txt
[[H2]] GET /users
Returns users.
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
