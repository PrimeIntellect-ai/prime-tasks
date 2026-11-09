#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs

    cat << 'EOF' > /home/user/configs/svc_alpha.csv
timestamp,param_name,param_value
2023-10-01 10:00:15,memory_mb,512
2023-10-01 10:00:15,memory_mb,512
2023-10-01 10:03:45,memory_mb,1024
EOF

    cat << 'EOF' > /home/user/configs/svc_beta.csv
timestamp,param_name,param_value
2023-10-01 10:01:30,memory_mb,256
2023-10-01 10:05:10,memory_mb,512
EOF

    chmod -R 777 /home/user
