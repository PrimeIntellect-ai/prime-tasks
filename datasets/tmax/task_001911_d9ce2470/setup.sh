#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/processed_data

    # Create dataset_alpha.csv in ISO-8859-1
    cat << 'EOF' > /home/user/raw_data/alpha_temp.csv
id;name;measure
1;café;12.5
2;jalapeño;8.4
EOF
    iconv -f UTF-8 -t ISO-8859-1 /home/user/raw_data/alpha_temp.csv > /home/user/raw_data/dataset_alpha.csv
    rm /home/user/raw_data/alpha_temp.csv

    # Create dataset_beta.json in UTF-16LE
    cat << 'EOF' > /home/user/raw_data/beta_temp.json
[
  {"id": 3, "name": "résumé", "measure": 4.1},
  {"id": 4, "name": "piñata", "measure": 9.9}
]
EOF
    iconv -f UTF-8 -t UTF-16LE /home/user/raw_data/beta_temp.json > /home/user/raw_data/dataset_beta.json
    rm /home/user/raw_data/beta_temp.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
