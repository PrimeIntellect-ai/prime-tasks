#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/papers.csv
paper_id,title,year,author_id
P1,A,2015,A1
P2,B,2016,A2
P3,C,2018,A1
P4,D,2019,A3
P5,E,2020,A2
P6,F,2021,A4
P7,G,2015,A3
P8,H,2018,A2
P9,I,2020,A4
P10,J,2023,A1
EOF

    cat << 'EOF' > /home/user/citations.csv
source_paper_id,target_paper_id
P2,P1
P3,P1
P4,P2
P5,P3
P6,P4
P8,P7
P9,P8
P10,P9
P9,P3
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
