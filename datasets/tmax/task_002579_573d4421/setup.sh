#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/priors.csv
id,x,prior
1,10,0.1
2,15,0.3
3,12,0.2
4,18,0.4
5,8,0.8
EOF

    cat << 'EOF' > /home/user/data/likelihoods.csv
id,y,likelihood
1,20,0.4
2,25,0.5
3,22,0.1
4,30,0.9
5,10,0.4
EOF

    cat << 'EOF' > /home/user/data/model_preds.csv
id,predicted_posterior
1,0.045
2,0.169
3,0.022
4,0.850
5,0.360
EOF

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
