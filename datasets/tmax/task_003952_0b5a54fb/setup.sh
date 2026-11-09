#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/pipeline_runs.csv
run_id,prior_alpha,prior_beta,heads,tails,estimated_mean,estimated_variance
run_1,1,1,10,5,0.6470,0.0126
run_2,2,2,50,50,0.5000,0.0023
run_3,1,5,20,5,0.8000,0.0500
run_4,10,10,100,20,0.7857,0.0011
run_5,5,2,0,10,0.2941,0.0115
EOF

    chmod -R 777 /home/user
