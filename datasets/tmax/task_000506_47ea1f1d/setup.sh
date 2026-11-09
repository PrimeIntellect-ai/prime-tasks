#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/system_metrics.csv
timestamp,cpu_util,mem_util,disk_io,net_tx
2023-10-01T10:00,85.0,40.0,100.0,10
2023-10-01T10:05,95.0,50.0,500.0,20
2023-10-01T10:10,20.0,80.0,50.0,5
2023-10-01T10:15,99.0,10.0,800.0,100
2023-10-01T10:20,90.0,0.0,200.0,50
EOF

    cat << 'EOF' > /home/user/model_weights.json
{
  "weights": {
    "cpu_util": 0.05,
    "disk_io": 0.001,
    "cpu_mem_ratio": 0.5
  },
  "bias": -6.0
}
EOF

    chmod -R 777 /home/user
