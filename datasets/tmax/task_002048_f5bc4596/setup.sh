#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/entities.csv
entity_id,entity_name
E01,Alpha Corp
E02,Bravo Ltd
E03,Charlie Inc
E04,Delta LLC
E05,Echo Group
E06,Foxtrot Co
E07,Golf SA
E08,Hotel PLC
E09,India GmbH
E10,Juliet NV
EOF

    cat << 'EOF' > /home/user/data/transactions.csv
source_id,target_id,amount
E01,E02,100
E02,E03,150
E03,E01,200
E03,E04,50
E04,E05,300
E05,E06,250
E06,E04,400
E01,E07,100
E07,E08,500
E08,E09,600
E09,E10,150
E10,E07,200
E03,E07,800
E02,E04,100
E08,E01,300
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
