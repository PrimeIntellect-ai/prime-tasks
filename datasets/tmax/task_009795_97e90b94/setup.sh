#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc gawk sed tar
    pip3 install pytest

    mkdir -p /home/user/artifacts/alpha/1.0
    mkdir -p /home/user/artifacts/beta/2.1
    mkdir -p /home/user/artifacts/gamma/0.9

    echo "binary_alpha" > /home/user/artifacts/alpha/1.0/bin.dat
    echo "binary_beta" > /home/user/artifacts/beta/2.1/bin.dat
    echo "binary_gamma" > /home/user/artifacts/gamma/0.9/bin.dat

    cat << 'EOF' > /home/user/artifacts/alpha/1.0/meta.json
{"name": "alpha", "version": "1.0", "status": "testing"}
EOF

    cat << 'EOF' > /home/user/artifacts/beta/2.1/meta.json
{"name": "beta", "version": "2.1", "status": "stable"}
EOF

    cat << 'EOF' > /home/user/artifacts/gamma/0.9/meta.json
{"name": "gamma", "version": "0.9", "status": "testing"}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/artifacts
    chmod -R 777 /home/user
