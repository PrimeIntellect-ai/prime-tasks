#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/citations.tsv
P001	P002
P001	P003
P001	P015
P002	P004
P003	P005
P004	P006
P005	P007
P006	P099
P007	P099
P015	P016
P016	P017
P017	P018
P018	P099
P001	P020
P020	P021
P021	P099
P090	P099
EOF
    chmod 644 /home/user/citations.tsv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
