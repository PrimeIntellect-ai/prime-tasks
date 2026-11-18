#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/old_configs
    mkdir -p /home/user/new_configs

    # us-east.csv
    cat << 'EOF' > /home/user/old_configs/us-east.csv
server_id,nginx_config,ssh_keys,env_vars
srv-101,"user www-data;
worker_processes auto;
pid /run/nginx.pid;","ssh-rsa AAAAB3NzaC1... user1@host","PROD=1
DEBUG=0"
srv-102,"user www-data;
worker_processes 4;","ssh-rsa AAA...","PROD=1"
EOF

    cat << 'EOF' > /home/user/new_configs/us-east.csv
server_id,nginx_config,ssh_keys,env_vars
srv-101,"user www-data;
worker_processes auto;
pid /var/run/nginx.pid;","ssh-rsa AAAAB3NzaC1... user1@host
ssh-rsa BBBBB user2@host","PROD=1
DEBUG=0"
srv-102,"user www-data;
worker_processes 4;","ssh-rsa AAA...","PROD=1"
EOF

    # eu-west.csv
    cat << 'EOF' > /home/user/old_configs/eu-west.csv
server_id,nginx_config,ssh_keys,env_vars
srv-201,"user www-data;","ssh-rsa CCC...","REGION=eu
TIMEOUT=30"
srv-202,"user root;
# bad config","",""
EOF

    cat << 'EOF' > /home/user/new_configs/eu-west.csv
server_id,nginx_config,ssh_keys,env_vars
srv-201,"user www-data;","ssh-rsa CCC...","REGION=eu
TIMEOUT=60"
srv-202,"user www-data;
# good config","",""
EOF

    chown -R user:user /home/user/old_configs /home/user/new_configs
    chmod -R 777 /home/user
