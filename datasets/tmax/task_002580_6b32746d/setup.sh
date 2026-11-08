#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip
    pip3 install pytest

    mkdir -p /home/user/backups
    mkdir -p /home/user/processing

    cd /tmp
    cat << 'EOF' > file1.csv
id,name,amount
1,Alice,100.50
2,Bob,200.00
EOF

    cat << 'EOF' > file2.csv
id,name,amount
3,Charlie,300.75
EOF

    cat << 'EOF' > file3.csv
id,name,amount
4,David,50.25
EOF

    zip /home/user/backups/financial_records.zip file1.csv file2.csv file3.csv
    rm file1.csv file2.csv file3.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
