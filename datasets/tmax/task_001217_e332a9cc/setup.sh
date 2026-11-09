#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/metrics.csv
c-web-01,45.2,1024.0
c-cache-02,1.2,30.5
c-db-03,3.0,150.0
c-worker-04,0.5,10.0
c-proxy-05,4.9,49.9
c-job-06,5.1,10.0
EOF

    chmod -R 777 /home/user
