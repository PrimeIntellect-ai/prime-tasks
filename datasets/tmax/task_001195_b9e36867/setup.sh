#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ruby perl
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_calibration.csv
x,y,status
1.0,2.2,valid
2.0,4.1,valid
-1.0,0.0,valid
3.0,6.0,valid
4.0,NaN,valid
5.0,9.9,error
6.0,12.1,valid
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
