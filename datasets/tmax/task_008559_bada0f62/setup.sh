#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/server_meta.csv
server_id,environment
srv-alpha,prod
srv-beta,staging
srv-gamma,prod
srv-delta,prod
EOF

    cat << 'EOF' > /home/user/raw_configs.log
[2023-11-01 08:00:00] srv-alpha 192.168.1.10 SSH_ROOT_LOGIN=no
[2023-11-01 08:00:00] srv-alpha 192.168.1.10 SSH_ROOT_LOGIN=no
[2023-11-01 08:15:00] srv-beta 10.0.0.2 SSH_ROOT_LOGIN=no
[2023-11-01 08:30:00] srv-delta 10.1.1.5 SSH_ROOT_LOGIN=yes
[2023-11-01 09:00:00] srv-alpha 192.168.1.10 SSH_ROOT_LOGIN=yes
[2023-11-01 09:00:00] srv-alpha 192.168.1.10 SSH_ROOT_LOGIN=yes
[2023-11-01 09:30:00] srv-gamma 172.16.1.1 SSH_ROOT_LOGIN=yes
[2023-11-01 10:00:00] srv-gamma 172.16.1.1 SSH_ROOT_LOGIN=no
[2023-11-01 10:30:00] srv-gamma 172.16.1.1 SSH_ROOT_LOGIN=yes
[2023-11-01 11:00:00] srv-beta 10.0.0.2 SSH_ROOT_LOGIN=yes
[2023-11-01 11:30:00] srv-alpha 192.168.1.10 SSH_ROOT_LOGIN=no
[2023-11-01 12:00:00] srv-alpha 192.168.1.10 SSH_ROOT_LOGIN=yes
[INVALID] srv-alpha 192.168.1.10 SSH_ROOT_LOGIN=yes
[2023-11-01 13:00:00] srv-delta 10.1.1.5 SSH_ROOT_LOGIN=no
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
