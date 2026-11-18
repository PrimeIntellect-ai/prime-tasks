#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
X,Y,Label
1,2.5,Valid
3,4.5,Valid
5,6.5,Valid
invalid,8.0,Error
10,11.5,Valid
EOF

    cat << 'EOF' > /home/user/weights.json
[0.5, 1.5]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
