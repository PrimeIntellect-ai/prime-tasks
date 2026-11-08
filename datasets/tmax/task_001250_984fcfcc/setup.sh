#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/alpha.json
[
  {"timestamp": 1620000000, "sensor": "A", "reading": 45.2},
  {"timestamp": 1620000060, "sensor": "A", "reading": 46.1}
]
EOF

    cat << 'EOF' > /home/user/raw_data/beta.csv
timestamp,sensor,reading
1620000120,B,42.8
1620000180,B,43.0
EOF

    cat << 'EOF' > /home/user/dataset_pipeline.conf
# Pipeline Configuration
/home/user/raw_data/alpha.json|/home/user/clean_data/alpha_exp|results.csv|csv|true
/home/user/raw_data/beta.csv|/home/user/clean_data/beta_exp|results.csv|csv|false
EOF

    chmod -R 777 /home/user
