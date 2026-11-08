#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/metadata.csv
ExpID,Category
E01,Target
E02,Target
E03,Ignore
E04,Target
E05,Target
E06,Target
EOF

    cat << 'EOF' > /home/user/data/series.csv
ExpID,V1,V2,V3,V4,V5
E01,10.0,20.0,30.0,40.0,50.0
E02,10.0,,30.0,150.0,50.0
E03,10.0,10.0,10.0,10.0,10.0
E04,11.0,19.0,31.0,42.0,49.0
E05,-10.0,0.0,,0.0,0.0
E06,12.0,18.0,32.0,43.0,48.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
