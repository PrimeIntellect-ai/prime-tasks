#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/experiments

    cat << 'EOF' > /home/user/experiments/raw_features.csv
id,f1,f2,f3,f4
data_1,1.0,2.0,3.0,4.0
data_2,0.5,0.5,2.0,1.0
data_3,2.0,1.0,1.5,2.0
EOF

    cat << 'EOF' > /home/user/experiments/target_embeddings.json
{
  "artifact_alpha": [1.7, 3.2],
  "artifact_beta": [0.6, 0.5],
  "artifact_gamma": [1.9, 0.7],
  "artifact_noise_1": [9.9, 9.9],
  "artifact_noise_2": [0.0, 0.0]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
