#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo build-essential libgsl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/experiment.csv
id,measurement_a,measurement_b,category
1,10.5,2.1,X
2,11.2,2.5,Y
3,9.8,1.9,X
4,10.1,2.2,X
5,12.0,3.0,Y
6,10.3,2.4,X
7,9.9,2.0,X
8,10.6,2.3,X
9,11.1,2.8,Y
10,10.0,2.1,X
EOF

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
