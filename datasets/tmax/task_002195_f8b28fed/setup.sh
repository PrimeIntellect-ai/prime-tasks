#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep bash
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/artifacts.csv
run_id,model_name,accuracy,loss,training_time
run_1,modelA,0.95,0.05,100
run_2,modelB,0.92,0.08,80
run_3,modelC,0.99,0.01,200
run_4,modelD,0.88,0.12,50
run_5,modelE,0.96,0.04,110
run_6,modelF,0.91,0.09,70
run_7,modelG,0.94,0.06,90
run_8,modelH,0.85,0.15,40
run_9,modelI,0.97,0.03,150
run_10,modelJ,0.90,0.10,60
EOF

    cat << 'EOF' > /home/user/embeddings.tsv
run_1|0.1|0.1|0.1|0.1|0.1
run_2|0.2|0.1|0.4|-0.2|0.5
run_3|0.3|0.3|0.3|0.3|0.3
run_4|0.5|0.5|0.1|0.1|0.1
run_5|0.4|0.4|0.4|0.4|0.4
run_6|0.1|-0.1|0.8|0.2|0.4
run_7|0.6|0.6|0.6|0.6|0.6
run_8|-0.2|0.8|0.1|-0.3|0.2
run_9|0.7|0.7|0.7|0.7|0.7
run_10|0.0|0.4|0.2|0.5|0.7
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
