#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/profiling_data.csv
run_id,N,time_ms
1,100,50
2,100,52
1,200,200
2,200,198
1,300,450
2,300,455
1,400,800
2,400,796
1,500,1250
2,500,1252
EOF

    chmod -R 777 /home/user
