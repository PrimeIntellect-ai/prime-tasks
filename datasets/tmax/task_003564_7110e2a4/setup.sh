#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/graph.csv
U001,VIEWS,C10
U001,VIEWS,C11
U002,VIEWS,C10
U003,VIEWS,C12
C10,INCLUDES,I501
C10,INCLUDES,I502
C11,INCLUDES,I503
C11,INCLUDES,I502
C12,INCLUDES,I504
U004,VIEWS,C13
C14,INCLUDES,I505
U001,FOLLOWS,U002
U002,LIKES,I501
U005,VIEWS,C10
C10,INCLUDES,I501
EOF

    cat << 'EOF' > /home/user/.expected_recommendations.csv
U001,3
U002,2
U003,1
U005,2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
