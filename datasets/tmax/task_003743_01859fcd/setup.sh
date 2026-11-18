#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar gzip
    pip3 install pytest

    mkdir -p /home/user/docs_temp/part1
    mkdir -p /home/user/docs_temp/part2

    cat << 'EOF' > /home/user/docs_temp/part1/api_v1.md
Status: DRAFT

# API V1
These are the old API docs. Do not publish.
EOF

    cat << 'EOF' > /home/user/docs_temp/part1/api_v2.md
Status: PUBLISHED

# API V2
These are the new API docs.
Use the endpoints carefully.
EOF

    cat << 'EOF' > /home/user/docs_temp/part2/setup_guide.md
Status: PUBLISHED

# Setup Guide
Run the installer to begin.
EOF

    cat << 'EOF' > /home/user/docs_temp/part2/random_notes.txt
Status: PUBLISHED

Just some random txt notes, not a markdown file.
EOF

    cat << 'EOF' > /home/user/docs_temp/part2/internal_arch.md
Status: INTERNAL

# Architecture
Internal systems details.
EOF

    cd /home/user/docs_temp/part1 && zip -q part1.zip api_v1.md api_v2.md
    cd /home/user/docs_temp/part2 && zip -q part2.zip setup_guide.md random_notes.txt internal_arch.md

    mkdir -p /home/user/docs_archive
    mv /home/user/docs_temp/part1/part1.zip /home/user/docs_archive/
    mv /home/user/docs_temp/part2/part2.zip /home/user/docs_archive/

    cd /home/user/docs_archive && tar -czf /home/user/incoming_docs.tar.gz part1.zip part2.zip

    rm -rf /home/user/docs_temp /home/user/docs_archive

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
