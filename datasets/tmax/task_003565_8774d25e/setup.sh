#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/raw_metrics.csv
Date,EventDescription,NodeAlpha,NodeBeta,NodeGamma
2023-10-01,"[E-404] Not Found",10,5,0
2023-10-01,"[E-500] Internal Error",0,20,5
2023-10-02,"[W-001] High Memory Usage",15,15,15
2023-10-02,"[E-404] Missing Resource",0,0,10
2023-10-03,"[I-100] Booting sequence",5,5,5
2023-10-03,"[E-500] Database Timeout",2,0,0
EOF

    cat << 'EOF' > /tmp/expected_summary.csv
NodeName,EventCode,TotalCount
NodeAlpha,E-404,10
NodeAlpha,E-500,2
NodeAlpha,I-100,5
NodeAlpha,W-001,15
NodeBeta,E-404,5
NodeBeta,E-500,20
NodeBeta,I-100,5
NodeBeta,W-001,15
NodeGamma,E-404,10
NodeGamma,E-500,5
NodeGamma,I-100,5
NodeGamma,W-001,15
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
