#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/config_changes.csv
ChangeID,AuthorEmail,CostImpact,CommitMessage
101,dev.ops@acme.corp,50,"Updated Nginx config"
102,hacker@bad.corp,-10,"Downgraded security
This should be dropped"
103,sarah.j@acme.corp,120,"Increased DB instances
Reason: Black Friday scaling
Approved by: Management"
104,bot@acme.corp,invalid,"Auto-commit"
105,admin@acme.corp,0,"Fixed typo in comments"
EOF

    chmod -R 777 /home/user
