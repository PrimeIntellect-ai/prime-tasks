#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/remote_archive

    cat << 'EOF' > /home/user/config_history.csv
Date,AppServer,DbServer,WebCache
2023-10-01,v1.2,v9.1,v2.0
2023-10-02,v1.3,v9.1,v2.1
2023-10-03,v1.3,v9.2,v2.1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
