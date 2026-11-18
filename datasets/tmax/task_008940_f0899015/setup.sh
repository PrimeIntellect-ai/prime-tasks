#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/measurements.txt
[2023-10-01 10:00:00] INFO - type: IC, variable: y0, value: 2.0
[2023-10-01 10:00:01] DEBUG - sensor check ok
[2023-10-01 10:00:02] INFO - type: PARAM, variable: mu, value: 1000.0
[2023-10-01 10:00:03] INFO - type: IC, variable: y1, value: 0.0
[2023-10-01 10:00:04] WARN - temperature fluctuation
[2023-10-01 10:00:05] INFO - type: CONFIG, variable: t_end, value: 3.0
EOF

    chmod -R 777 /home/user
