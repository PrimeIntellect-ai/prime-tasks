#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar
    pip3 install pytest

    mkdir -p /home/user/setup_tmp/engineering/backend
    mkdir -p /home/user/setup_tmp/engineering/frontend

    # Create backend files
    cat << 'EOF' > "/home/user/setup_tmp/engineering/backend/API Specs.txt.old"
Title: Backend API
Draft: Yes
Company: AcmeCorp
Description: This is the API specification for AcmeCorp systems.
EOF

    cat << 'EOF' > "/home/user/setup_tmp/engineering/backend/DB Schema.md.draft"
Title: Database Schema
Draft: Yes
Property of AcmeCorp.
EOF

    # Create frontend files
    cat << 'EOF' > "/home/user/setup_tmp/engineering/frontend/UI Components.txt.old"
Title: UI Components
Draft: Yes
Company: AcmeCorp
Contains AcmeCorp standard buttons.
EOF

    cat << 'EOF' > "/home/user/setup_tmp/engineering/frontend/Styling Guide.md.draft"
Title: Styling Guide
Draft: Yes
Design system for AcmeCorp.
EOF

    # Create nested archives
    cd /home/user/setup_tmp/engineering/backend
    zip backend.zip "API Specs.txt.old" "DB Schema.md.draft"
    rm "API Specs.txt.old" "DB Schema.md.draft"

    cd /home/user/setup_tmp/engineering/frontend
    tar -czf frontend.tar.gz "UI Components.txt.old" "Styling Guide.md.draft"
    rm "UI Components.txt.old" "Styling Guide.md.draft"

    # Create outer archive
    cd /home/user/setup_tmp
    tar -czf /home/user/raw_docs.tar.gz engineering/

    # Cleanup
    rm -rf /home/user/setup_tmp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
