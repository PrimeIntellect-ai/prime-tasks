#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl zip tar libc-bin
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create hr_data.csv with Windows-1252 encoding
    cat << 'EOF' > hr_data_utf8.csv
id,name,role
1,José Guitiérrez,Manager
2,Müller Schmidt,Analyst
3,Renée Dubois,Developer
EOF
    iconv -f UTF-8 -t WINDOWS-1252 hr_data_utf8.csv > hr_data.csv
    rm hr_data_utf8.csv

    # Create finance_data.json with UTF-16 encoding
    cat << 'EOF' > finance_data_utf8.json
[
  {"tx_id": "A100", "amount": 1500.50, "currency": "€"},
  {"tx_id": "A101", "amount": 300.00, "currency": "£"}
]
EOF
    iconv -f UTF-8 -t UTF-16 finance_data_utf8.json > finance_data.json
    rm finance_data_utf8.json

    # Create the legacy tarball
    tar -czf legacy_data.tar.gz hr_data.csv finance_data.json
    rm hr_data.csv finance_data.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
