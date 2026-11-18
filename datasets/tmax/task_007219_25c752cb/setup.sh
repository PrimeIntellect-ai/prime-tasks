#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/source_a.csv
ExperimentID,Metric1,Metric2
1,10.0,12.0
2,-999.0,8.0
3,15.0,-999.0
4,25.0,20.0
5,5.0,5.0
EOF

    cat << 'EOF' > /home/user/source_b.csv
ExperimentID,Metric3,PriorProb
1,5.0,0.5
2,10.0,0.6
3,15.0,0.4
4,25.0,0.2
5,-999.0,0.8
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
