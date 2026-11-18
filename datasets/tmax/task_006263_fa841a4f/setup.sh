#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/loc_data

    cat << 'EOF' > /home/user/loc_data/en_to_fr.csv
Date,ID,Length
2023-10-01T10:00:00Z,STR_A,10
2023-10-01T10:15:00Z,STR_B,20
EOF

    cat << 'EOF' > /home/user/loc_data/en_to_de.json
[
  {"timestamp": 1696156200, "key": "STR_C", "chars": 30},
  {"timestamp": 1696158000, "key": "STR_D", "chars": 15}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
