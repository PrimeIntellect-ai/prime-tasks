#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/etl_dependencies.csv
dependent_job,upstream_job
JobB,JobA
JobC,JobB
JobA,JobC
JobD,JobC
JobE,JobD
JobC,JobE
JobF,JobE
JobG,JobF
JobH,JobG
JobF,JobH
JobI,JobH
JobJ,JobI
JobX,JobC
JobY,JobX
JobZ,JobY
JobK,JobD
JobL,JobK
EOF

    chmod -R 777 /home/user
