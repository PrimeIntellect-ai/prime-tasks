#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/configs

    cat << 'EOF' > /home/user/server_info.csv
ServerName,Environment
alpha,prod
beta,prod
gamma,prod
delta,dev
epsilon,dev
zeta,dev
EOF

    cat << 'EOF' > /home/user/configs/alpha.conf
log_level=info
max_connections=100
timeout=30
enable_cache=true
feature_x=on
EOF

    cat << 'EOF' > /home/user/configs/beta.conf
log_level=info
max_connections=100
timeout=30
enable_cache=true
feature_x=on
EOF

    cat << 'EOF' > /home/user/configs/gamma.conf
log_level=info
max_connections=100
timeout=30
enable_cache=true
feature_x=off
EOF

    cat << 'EOF' > /home/user/configs/delta.conf
log_level=debug
max_connections=50
timeout=60
EOF

    cat << 'EOF' > /home/user/configs/epsilon.conf
log_level=debug
max_connections=50
enable_cache=false
feature_y=on
EOF

    cat << 'EOF' > /home/user/configs/zeta.conf
log_level=debug
max_connections=50
enable_cache=false
feature_y=on
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
