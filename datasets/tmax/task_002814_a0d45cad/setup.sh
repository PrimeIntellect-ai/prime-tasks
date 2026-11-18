#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make sed gawk vim coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/docs_target/api/v1
    mkdir -p /home/user/docs_target/guides
    mkdir -p /home/user/update_pkg

    # Create initial target files
    echo "Welcome to [COMPANY_NAME] API v1." > /home/user/docs_target/api/v1/intro.md
    echo "Auth details for [COMPANY_NAME]." > /home/user/docs_target/api/v1/auth.md
    echo "User guide for [COMPANY_NAME] product." > /home/user/docs_target/guides/user.md

    # Create update package files
    echo "Updated auth details for [COMPANY_NAME]. Token required." > /home/user/update_pkg/new_auth.md
    echo "New admin guide for [COMPANY_NAME]." > /home/user/update_pkg/admin.md
    echo "MALICIOUS CONTENT" > /home/user/update_pkg/exploit.txt

    # Create manifest with directory traversal attempts
    cat << 'EOF' > /home/user/update_pkg/manifest.txt
api/v1/auth.md | new_auth.md
guides/admin.md | admin.md
../malicious.txt | exploit.txt
guides/../../system_overwrite.txt | exploit.txt
api/v1/../v2/new.md | admin.md
EOF

    chown -R user:user /home/user/docs_target /home/user/update_pkg
    chmod -R 777 /home/user
