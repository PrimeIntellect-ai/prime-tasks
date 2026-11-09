#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/train_data.csv
1,a8f9e,0.95,0.855
2,b2c4d,0.12,0.900
3,c9x1z,0.45,0.760
4,d4f2a,0.88,0.999
5,e5h7k,0.33,0.500
EOF

    cat << 'EOF' > /home/user/test_data.csv
10,z1x2c,0.95,0.850
11,a8f9e,0.95,0.810
12,m4n5b,0.12,0.910
13,b2c4d,0.12,0.925
14,p9o8i,0.88,0.990
15,e5h7k,0.33,0.500
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
