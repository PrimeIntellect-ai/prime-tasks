#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/pipeline_export.csv
task_id,status,dependencies
JobA,active,JobB,JobG
JobB,active,JobC
JobC,active,JobA
JobD,active,JobE
JobE,active,JobF
JobF,inactive,JobD
JobG,active,JobH
JobH,active,JobI
JobI,active,JobG
JobJ,active,JobK
JobK,active
EOF

    chmod -R 777 /home/user
