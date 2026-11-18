#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/
    cat << 'EOF' > /home/user/artifact_manifest.csv
app.tar.gz,1500,0644
deploy.sh,250,0755
config.yml,120,0600
server.bin,8192,0700
readme.txt,42,0444
EOF

    chmod -R 777 /home/user
