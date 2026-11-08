#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/data /home/user/pipeline

    cat << 'EOF' > /home/user/data/raw_translations.csv
Timestamp,JobId,StringId,TranslatorId,WordCount,DurationSeconds
1620000000,J1,S1,T1,200,600
1620000010,J1,S2,T2,150,300
1620000050,J1,S1,T1,200,600
1620000020,J2,S1,T1,500,1200
1620000030,J2,S2,T1,100,150
1620000040,J2,S3,T2,300,900
1620000015,J1,S2,T2,150,300
1620000060,J3,S1,T1,400,1000
1620000070,J3,S2,T2,250,750
1620000080,J4,S1,T1,120,240
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
