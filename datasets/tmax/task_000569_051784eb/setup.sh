#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv tar gzip
    pip3 install pytest

    mkdir -p /home/user/data/raw

    cat << 'EOF' > /home/user/data/raw/matrix_1.csv
2.5,1.0,0.0
0.0,4.5,2.0
1.0,1.0,3.0
EOF

    cat << 'EOF' > /home/user/data/raw/matrix_2.csv
10.0,2.0,3.0
1.0,10.0,5.0
2.0,2.0,5.12
EOF

    cat << 'EOF' > /home/user/data/raw/matrix_3.csv
5.0,5.0,5.0
0.0,7.99,0.0
1.0,1.0,7.0
EOF

    cat << 'EOF' > /home/user/data/raw/matrix_4.csv
15.0,0.0,0.0
0.0,10.5,0.0
0.0,0.0,5.0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chmod -R 777 /home/user
