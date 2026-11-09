#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        default-jre-headless \
        golang \
        wget \
        curl

    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/network.csv
subject,predicate,object
user1,knows,user2
user2,knows,user3
user3,knows,user4
user1,likes,user5
user4,likes,user6
user4,knows,user7
user8,knows,user1
EOF

    chmod -R 777 /home/user
