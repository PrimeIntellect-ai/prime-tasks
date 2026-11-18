#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/dataset_dependencies.tsv
Upstream	Downstream
DS_001	DS_002
DS_002	DS_003
DS_002	DS_004
DS_005	DS_006
DS_006	DS_007
DS_006	DS_010
DS_007	DS_011
DS_010	DS_011
DS_011	DS_012
DS_012	DS_013
DS_015	DS_006
DS_013	DS_014
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
