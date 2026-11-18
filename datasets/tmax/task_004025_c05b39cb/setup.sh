#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/artifacts/exp_alpha.csv
id,ground_truth,prediction
1,the quick brown fox,the fast brown fox
2,jumps over the lazy dog,leaps over a lazy dog
EOF

    cat << 'EOF' > /home/user/artifacts/exp_beta.csv
id,ground_truth,prediction
1,the quick brown fox,the quick brown fox
2,jumps over the lazy dog,walks around the sleepy cat
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
