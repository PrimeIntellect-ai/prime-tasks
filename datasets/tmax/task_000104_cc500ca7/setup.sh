#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/daily_loc_stats.csv
Date,Project,EN,FR,ES
2023-10-01,AppA,100,90,95
2023-10-01,AppB,50,50,45
2023-10-02,AppA,120,110,105
2023-10-02,AppB,55,50,45
2023-10-03,AppA,130,120,115
2023-10-03,AppB,60,30,40
2023-10-04,AppA,140,130,125
2023-10-04,AppB,60,40,40
2023-10-05,AppA,150,140,135
2023-10-05,AppB,60,40,40
EOF

    chmod -R 777 /home/user
