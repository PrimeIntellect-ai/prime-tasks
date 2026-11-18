#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk time
    pip3 install pytest

    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/artifacts/registry.csv
id,timestamp,size_bytes,filename
art-001,1678886400,104857600,release-v1.tar.gz
art-002,1678886450,50000000,debug-symbols.zip
art-003,1678886500,2097152,docs.pdf
art-004,1678886550,0,empty.log
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
