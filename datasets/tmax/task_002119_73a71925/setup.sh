#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang systemd sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/input
    mkdir -p /home/user/output
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/input/configs.jsonl
{"server_id": "srv-A", "reported_at": 1672531200, "config_data": {"app_version": "1.0.0", "max_conns": 50, "features": {"tls": false}}}
{"server_id": "srv-A", "reported_at": "2023-01-01T01:00:00Z", "config_data": {"app_version": "1.0.0", "max_conns": 50, "features": {"tls": false}}}
{"server_id": "srv-A", "reported_at": "2023-01-01 02:00:00", "config_data": {"app_version": "1.1.0", "max_conns": 100, "features": {"tls": true}}}
{"server_id": "srv-B", "reported_at": "2023-01-01 00:30:00", "config_data": {"app_version": "2.0.0", "max_conns": 200, "features": {"tls": true}}}
{"server_id": "srv-B", "reported_at": 1672534800, "config_data": {"app_version": "2.0.0", "max_conns": 200, "features": {"tls": true}}}
{"server_id": "srv-B", "reported_at": "2023-01-01T02:30:00Z", "config_data": {"app_version": "2.0.1", "max_conns": 200, "features": {"tls": true}}}
EOF

    cat << 'EOF' > /home/user/output/expected_changelog.csv
server_id,timestamp,config_hash,app_version,max_conns,tls
srv-A,1672531200,7f6b95a43b2edfe333c1621bfdf6bb90df21f8a8461ab7fb24dfcb8b32cf05d2,1.0.0,50,false
srv-A,1672538400,c1c7d2c3e1db282de7022068ed1fcb262a4d04c4146059e6c6ffc591cc5a8b5e,1.1.0,100,true
srv-B,1672533000,46376c7c4b4d6a63d91ea11c5ab1eebf3efb250dd68edb7e2c9ef8f0b073999e,2.0.0,200,true
srv-B,1672540200,1e813f412c1b2f7a91a92a5b672721867e0e719ed0ea9a4e09f7a7751c1d0af9,2.0.1,200,true
EOF

    chown -R user:user /home/user/input /home/user/output /home/user/app
    chmod -R 777 /home/user
