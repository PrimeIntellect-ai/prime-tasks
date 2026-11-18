#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/patients.csv
PatientID,Age,Condition
1,45,Healthy
2,60,AtRisk
3,30,Healthy
4,75,Critical
EOF

    cat << 'EOF' > /home/user/data/measurements.csv
PatientID,BiomarkerA,BiomarkerB
3,1.8,2.0
1,2.5,1.2
4,4.5,0.0
2,3.1,0.5
EOF

    chmod -R 777 /home/user
