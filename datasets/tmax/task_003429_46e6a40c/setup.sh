#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/embeddings.csv
run_1,0.1,0.2,0.3,0.4,0.5
run_2,0.8,0.1,0.1,0.1,0.1
target_run,0.5,0.5,0.2,0.2,0.2
run_3,0.9,0.9,0.9,0.9,0.9
run_4,0.4,0.5,0.2,0.3,0.1
run_5,0.2,0.2,0.2,0.2,0.2
EOF

    chmod -R 777 /home/user
