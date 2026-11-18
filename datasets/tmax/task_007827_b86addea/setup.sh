#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/evaluation_pipeline

    cat << 'EOF' > /home/user/data/ground_truth.csv
id,fold_id,true_value
1,1,10.5
2,1,12.0
3,2,9.0
4,2,8.5
5,3,15.0
6,3,14.5
7,4,20.0
8,4,21.0
9,5,5.0
10,5,6.5
EOF

    cat << 'EOF' > /home/user/data/preds_alpha.csv
id,pred_value
1,10.0
2,11.5
3,9.5
4,8.0
5,16.0
6,14.0
7,21.0
8,20.0
9,5.5
10,6.0
EOF

    cat << 'EOF' > /home/user/data/preds_beta.csv
id,pred_value
1,12.0
2,14.0
3,10.0
4,10.0
5,13.0
6,12.0
7,25.0
8,26.0
9,3.0
10,4.0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
