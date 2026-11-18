#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data_project/raw

    cat << 'EOF' > /home/user/data_project/raw/data1.json
{
  "record_id": "A001",
  "user_name": "Alice Smith",
  "epoch_time": 1609459200
}
EOF

    cat << 'EOF' > /home/user/data_project/raw/data2.json
{
  "record_id": "B022",
  "user_name": "Bob Jones",
  "epoch_time": 1641042000
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
