#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/preds.txt
1 1.2
2 3.5
3 4.1
4 6.2
5 6.0
6 9.5
7 8.0
EOF

    cat << 'EOF' > /home/user/truth.txt
1 1.0
2 4.0
3 4.0
4 5.0
5 6.0
6 8.0
7 8.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
