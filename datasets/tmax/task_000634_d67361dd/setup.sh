#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest mlflow

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/mlruns

    cat << 'EOF' > /home/user/raw_logs.csv
id,message
1,"System error: process fail!"
2,"Need help with the new setup."
3,"Warning: fail fail fail"
4,"Can someone help with this error?"
5,"All systems operational."
EOF

    cat << 'EOF' > /home/user/config.json
{
  "prior_urgent": 0.1,
  "likelihoods": {
    "error": {"urgent": 0.8, "normal": 0.05},
    "fail": {"urgent": 0.6, "normal": 0.1},
    "help": {"urgent": 0.5, "normal": 0.2}
  }
}
EOF

    chmod -R 777 /home/user
