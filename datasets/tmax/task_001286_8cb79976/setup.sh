#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups/raw
    mkdir -p /home/user/backups/processed

    cat << 'EOF' > /home/user/backups/raw/logA.csv
id,date,event
101,2024-05-01,login
102,2024-05-01,logout
EOF

    cat << 'EOF' > /home/user/backups/raw/logB.json
[
  {"id": 103, "date": "2024-05-02", "event": "upload"},
  {"id": 104, "date": "2024-05-02", "event": "download"}
]
EOF

    cat << 'EOF' > /home/user/backups/raw/logC.csv
id,date,event
101,2024-05-01,login
102,2024-05-01,logout
EOF

    cat << 'EOF' > /home/user/backups/raw/logD.json
[
  {"id": 99, "date": "2024-04-30", "event": "register"}
]
EOF

    chown -R user:user /home/user/backups
    chmod -R 777 /home/user
