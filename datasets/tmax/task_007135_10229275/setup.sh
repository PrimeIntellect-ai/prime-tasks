#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/calibration.csv
x_true,y_obs
1.0,1.7
2.0,4.6
3.0,9.9
4.0,18.8
5.0,32.5
EOF

    cat << 'EOF' > /home/user/raw_features.csv
y_obs
1.7
4.6
18.8
24.832
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
