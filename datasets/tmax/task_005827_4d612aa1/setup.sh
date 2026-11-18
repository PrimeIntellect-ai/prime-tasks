#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tar gzip gawk sed
    pip3 install pytest

    mkdir -p /home/user/docs_temp
    cat << 'EOF' > /home/user/docs_temp/draft_logs.txt
Author: Alice
Doc: API_Reference
Status: Draft
---
Author: Bob
Doc: User_Guide
Status: Review
---
Author: Charlie
Doc: Release_Notes
Status: Final
---
EOF

    cd /home/user/docs_temp
    tar -czf /home/user/docs.tar.gz draft_logs.txt
    cd /home/user
    rm -rf /home/user/docs_temp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
