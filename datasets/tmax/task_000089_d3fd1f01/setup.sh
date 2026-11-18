#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_config.csv
1710000000, Max_Workers , 5
1710000000,max_workers, 8
1710000010, MAX_WORKERS, 12
1710000010, other_param, 50
1710000040, max_Workers, 10
1710000060, max_workers, 15
1710000060, max_workers, 15
1710000090, max_workers, 14
EOF

    chmod -R 777 /home/user
