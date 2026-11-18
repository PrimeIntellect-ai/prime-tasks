#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor1.csv
id,f1,f2
1,10.0,20.0
2,15.0,25.0
3,12.0,22.0
EOF

    cat << 'EOF' > /home/user/sensor2.csv
id,f3,f4
3,5.0,2.0
1,8.0,4.0
2,6.0,3.0
EOF

    cat << 'EOF' > /home/user/pca_weights.txt
0.5 0.5
-0.5 0.5
0.5 -0.5
-0.5 -0.5
EOF

    cat << 'EOF' > /home/user/model_weights.txt
1.0
-1.0
EOF

    chmod -R 777 /home/user
