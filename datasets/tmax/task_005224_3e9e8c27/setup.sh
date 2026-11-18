#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk coreutils grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/models

    cat << 'EOF' > /home/user/data/features.csv
id,f1,f2,f3
1,0.5,1.2,-0.3
2,-0.1,0.8,0.9
3,1.5,-0.5,0.2
4,0.0,0.0,0.0
5,2.1,1.1,-1.1
6,-1.0,-1.0,-1.0
EOF

    cat << 'EOF' > /home/user/data/metadata.csv
id,timestamp,model_version
1,1620000000,v2
2,1620000100,v1
3,1620000200,v2
4,1620000300,v2
5,1620000400,v3
6,1620000500,v2
EOF

    cat << 'EOF' > /home/user/models/v2_weights.txt
0.5,-0.2,1.1,0.1
EOF

    chmod -R 777 /home/user
