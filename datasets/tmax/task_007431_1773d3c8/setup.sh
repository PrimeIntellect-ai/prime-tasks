#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/requests.txt
1000 1 0,0 4,0 4,3 0,3
1500 2 0,0 10,0 5,5
1800 1 0,0 2,0 2,2 0,2
1950 1 0,0 1,0 1,1 0,1
2500 1 0,0 5,0 5,5 0,5
2600 2 1,1 4,1 4,5 1,5
3000 2 0,0 2,0 2,2 0,2
EOF

    chmod -R 777 /home/user
