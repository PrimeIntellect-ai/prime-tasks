#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output
    mkdir -p /home/user/analyzer

    cat << 'EOF' > /home/user/data/metadata.csv
paper_id,year,impact_score
P01,2020,45
P02,2020,62
P03,2021,55
P04,2021,80
P05,2022,91
P06,2022,88
P07,2019,30
P08,2019,40
P09,2020,75
EOF

    cat << 'EOF' > /home/user/data/citations.txt
P01,P02
P02,P03
P03,P01
P04,P05
P05,P06
P06,P04
P01,P04
P07,P08
P08,P07
P09,P04
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data /home/user/output /home/user/analyzer
    chmod -R 777 /home/user
