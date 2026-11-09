#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/datasets.csv
id,name,size_mb
1,Root Dataset,100
2,Cleaned Data,200
3,Filtered Data,150
4,Aggregated Data A,300
5,Aggregated Data B,250
6,Final Report Data,400
EOF

    cat << 'EOF' > /home/user/derivations.csv
source_id,target_id,processing_time_mins
1,2,10
1,3,15
2,4,5
3,4,20
4,5,10
3,6,30
2,6,10
5,6,5
EOF

    chmod -R 777 /home/user
