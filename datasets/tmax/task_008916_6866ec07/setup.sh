#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
TrialID,LabName,Measurement
101, Alpha ,10.5
102,BETA,20.0
101,alpha,10.5
103, alpha ,
104, gamma ,15.0
105,BETA,NaN
106,BETA,22.0
102, beta ,20.0
107, DELTA, 5.0
108,delta,
EOF

    chmod -R 777 /home/user
