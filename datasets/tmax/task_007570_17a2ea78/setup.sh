#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_configs

    cat << 'EOF' > /home/user/raw_configs/app1_2023-10-01.ini
HostName=prod-db
Password=supersecret
Port=5432
EOF

    cat << 'EOF' > /home/user/raw_configs/app1_2023-10-03.ini
HostName=prod-db
Password=changedsecret
Port=5432
EOF

    cat << 'EOF' > /home/user/raw_configs/app2_2023-10-02.json
{
  "APIKey": "A1B2C3D4",
  "Endpoint": "https://api.example.com",
  "RetryCount": "3"
}
EOF

    cat << 'EOF' > /home/user/raw_configs/app2_2023-10-05.json
{
  "APIKey": "E5F6G7H8",
  "Endpoint": "https://api.example.com",
  "RetryCount": "5"
}
EOF

    chown -R user:user /home/user/raw_configs
    chmod -R 777 /home/user
