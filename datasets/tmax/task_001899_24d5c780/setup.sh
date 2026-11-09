#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/etl_dump.csv
101,1620000000, Alice ,45.5,First note
101,1620000010, ALICE,NA,Retry note!
102,1620000020,Bob,NA,No measurement here...
103,1620000030, ChArLiE,50.0,Valid row with résumé
103,1620000040,charlie ,NA,Valid row with resume
104,1620000050,  DAVE  ,,Empty measurement field
EOF
    chmod 644 /home/user/etl_dump.csv

    cat << 'EOF' > /home/user/.expected_clean_data.csv
101,alice,45.5,2
102,bob,45.5,3
103,charlie,50.0,4
104,dave,50.0,3
EOF
    chmod 644 /home/user/.expected_clean_data.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
