#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scipy scikit-learn numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/dataset.csv
record_id,measurement,notes
1,45.2,normal operation detected
2,NaN,system failure missing data
3,1050.5,extreme spike in temperature
4,44.8,stable baseline reading recorded
5,-5.0,sensor calibration error
6,46.1,routine check baseline
7,45.9,stable operation
EOF

    chmod 644 /home/user/dataset.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
