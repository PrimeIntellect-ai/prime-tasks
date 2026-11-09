#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/audit_data

    cat << 'EOF' > /home/user/audit_data/accounts.csv
A100,LOW
A101,LOW
A102,HIGH
A103,HIGH
A104,LOW
A105,HIGH
EOF

    cat << 'EOF' > /home/user/audit_data/transfers.csv
T1,A100,A101,5000
T2,A101,A102,6000
T3,A100,A104,8000
T4,A104,A103,3000
T5,A104,A102,2000
T6,A100,A102,1000
T7,A101,A105,12000
T8,A100,A105,15000
EOF

    cat << 'EOF' > /tmp/expected_flagged_paths.csv
A102,A100->A101->A102,11000,1
A102,A100->A104->A102,10000,2
A102,A100->A102,1000,3
A103,A100->A104->A103,11000,1
A105,A100->A101->A105,17000,1
A105,A100->A105,15000,2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
