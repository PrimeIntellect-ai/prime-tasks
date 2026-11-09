#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
x,true_y
-2.0, -1.0
-1.5, 0.5
-1.0, 1.2
-0.5, 2.0
0.0, 2.4
0.5, 2.9
1.0, 3.5
1.5, 3.8
2.0, 4.0
2.5, 3.7
EOF

    chmod -R 777 /home/user
