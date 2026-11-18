#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/docs_raw

    cat << 'EOF' > /home/user/docs_raw/intro.md
Welcome to AcmeCorp API v1.0. This is the intro to AcmeCorp.
EOF

    cat << 'EOF' > /home/user/docs_raw/setup.md
To setup AcmeCorp software v1.0, run the installer. AcmeCorp rocks.
EOF

    cat << 'EOF' > /home/user/docs_raw/api.md
AcmeCorp v1.0 has 5 endpoints. Contact AcmeCorp support.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
