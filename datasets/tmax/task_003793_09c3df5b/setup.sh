#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest packaging semver

    mkdir -p /home/user/build_logs

    cat << 'EOF' > /home/user/build_logs/v1.0.0.log
ALLOC 400000
FREE 100000
ALLOC 50000
EOF

    cat << 'EOF' > /home/user/build_logs/v1.2.0.log
ALLOC 300000
ALLOC 300000
FREE 100000
EOF

    cat << 'EOF' > /home/user/build_logs/v1.10.0.log
ALLOC 250000
ALLOC 200000
FREE 400000
EOF

    cat << 'EOF' > /home/user/build_logs/v2.0.0.log
ALLOC 550000
FREE 550000
EOF

    cat << 'EOF' > /home/user/build_logs/v1.9.5.log
ALLOC 490000
FREE 100000
EOF

    cat << 'EOF' > /home/user/build_logs/v1.9.11.log
ALLOC 400000
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
