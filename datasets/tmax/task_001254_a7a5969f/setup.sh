#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/versions.txt
1.0.0
1.9.9
2.0.0-alpha
2.0.0-rc1
2.0.0-rc2
2.0.0
2.0.1
3.0.0-beta
EOF

    chmod -R 777 /home/user
