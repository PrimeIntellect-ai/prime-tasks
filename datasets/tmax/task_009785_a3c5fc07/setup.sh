#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/graph.txt
1 2
1 3
2 3
3 4
4 5
EOF

    cat << 'EOF' > /home/user/labels.txt
1 0.10
2 0.20
3 0.80
4 0.30
5 0.05
EOF

    chmod -R 777 /home/user
