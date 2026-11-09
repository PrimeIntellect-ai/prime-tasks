#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/batch1.csv
id,timestamp,log_message
1,1620000000,Connection timeout on database port 5432.
2,1620000010,Connection timeout on database port 5432! [RETRY]
3,1620000050,Successful extraction of 500 rows.
4,1620000060,Successful extraction of 500 rows. [RETRY]
EOF

    cat << 'EOF' > /home/user/data/batch2.json
[
  {
    "id": 5,
    "timestamp": 1620000100,
    "log_message": "Memory limit exceeded during aggregation phase."
  },
  {
    "id": 6,
    "timestamp": 1620000105,
    "log_message": "Memory limit exceeded during aggregation phase. Retrying block."
  },
  {
    "id": 7,
    "timestamp": 1620000200,
    "log_message": "Pipeline finished successfully with 0 errors."
  }
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
