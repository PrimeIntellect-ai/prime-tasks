#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/artifacts.csv
run_id,latency_ms,cpu_usage_pct,memory_mb,validation_loss
1,45.2,60.1,250.4,0.45
2,46.1,62.3,280.1,0.42
3,50.3,58.9,210.5,0.48
4,42.8,65.0,305.2,0.39
5,55.4,55.2,190.8,0.51
6,48.9,61.4,265.7,0.44
7,47.2,60.8,240.2,0.46
8,49.1,59.7,225.6,0.47
9,44.5,63.1,290.4,0.41
10,51.2,57.5,200.9,0.50
EOF

    chmod -R 777 /home/user
