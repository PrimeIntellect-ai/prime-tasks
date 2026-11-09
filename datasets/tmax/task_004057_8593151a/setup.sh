#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy python3-scipy
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sequences.json
{
  "target": "ATGCACGTGACTAGCTACGATCGATCGTACGATCGATCGATCG",
  "background": "ATATATATATGCGCATATATATATATATATATATATATATATA"
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
