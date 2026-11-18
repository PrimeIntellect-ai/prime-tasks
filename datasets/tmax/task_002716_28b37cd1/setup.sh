#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/dataset_raw/zone_A
    mkdir -p /home/user/dataset_raw/zone_B/subzone
    mkdir -p /home/user/dataset_raw/zone_C
    mkdir -p /home/user/summary

    cat << 'EOF' > /home/user/dataset_raw/zone_A/log1.cst
2:MjAyMy0xMC0wMVQxMDowMDowMHxTMDh8MTUuMnxOT1JNQUw=
1:MjAyMy0xMC0wMVQxMDowMTowMHxTMDF8OTkuOXxDUklUSUNBTA==
EOF

    cat << 'EOF' > /home/user/dataset_raw/zone_B/subzone/log2.cst
3:MjAyMy0xMC0wMVQxMToxMjowMHxTMDJ8MTAuMXxOT1JNQUw=
2:MjAyMy0xMC0wMVQxMTozNDowMHxTMDN8MTA1LjJ8Q1JJVElDQUw=
EOF

    cat << 'EOF' > /home/user/dataset_raw/zone_C/log3.cst
1:MjAyMy0xMC0wMVQwOToyMjowMHxTMDV8ODguOHxDUklUSUNBTA==
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
