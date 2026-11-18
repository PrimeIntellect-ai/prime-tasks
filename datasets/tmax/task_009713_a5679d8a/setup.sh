#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/datasets_meta.csv
dataset_id,num_rows,num_features,missing_pct,feature_mean,feature_std
DS_Target,1000,50,0.05,10.0,2.0
DS_A,950,48,,10.1,2.1
DS_B,1050,52,0.06,12.5,3.0
DS_C,-100,20,0.10,5.0,1.0
DS_D,800,45,0.02,9.8,0.0
DS_E,1200,60,0.04,10.5,1.8
DS_F,1000,50,0.08,9.9,1.9
EOF

    chmod -R 777 /home/user
