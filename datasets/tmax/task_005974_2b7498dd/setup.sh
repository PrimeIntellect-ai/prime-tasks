#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/auth_sys.log
[2023-10-24 14:15:00] Event: FAILED_LOGIN User: Admin_2 IP: 192.168.1.50 Msg: Bad password
[2023-10-24 14:35:12] Event: FAILED_LOGIN User: ADMIN_2 IP: 192.168.1.50 Msg: Bad password
[2023-10-24 14:45:00] Event: SUCCESS_LOGIN User: Admin_2 IP: 192.168.1.50 Msg: Success
[2023-10-24 14:50:00] Event: FAILED_LOGIN User: Bo IP: 10.0.0.1 Msg: User too short
[2023-10-24 14:51:00] Event: FAILED_LOGIN User: Toolongusername_123 IP: 10.0.0.1 Msg: User too long
[2023-10-24 14:55:00] Event: FAILED_LOGIN User: Invalid@User IP: 10.0.0.1 Msg: Invalid chars
[2023-10-24 15:05:00] Event: FAILED_LOGIN User: Valid_User IP: 999.999.999.999 Msg: Valid format IP
[2023-10-24 15:10:00] Event: FAILED_LOGIN User: Valid_User IP: 10.0.0.a Msg: Invalid format IP
[2023-10-24 15:15:00] Event: FAILED_LOGIN User: Valid_User IP: 10.0.0.1.5 Msg: Invalid format IP
[2023-10-24 16:01:00] Event: FAILED_LOGIN User: Bob IP: 10.0.0.2 Msg: Failed
[2023-10-24 16:05:00] Event: FAILED_LOGIN User: bob IP: 10.0.0.2 Msg: Failed
[2023-10-24 16:10:00] Event: FAILED_LOGIN User: alice IP: 192.168.0.1 Msg: Failed
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
