#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project

    touch /home/user/project/processor.py
    touch /home/user/project/helper.py
    touch /home/user/project/network.py
    touch /home/user/project/utils.py

    cat << 'EOF' > /home/user/ids_alerts.log
[2023-10-24 09:12:33] [INFO-SYS-00] System startup complete
[2023-10-24 10:05:01] [ALERT-SBX-09] Suspicious activity in /home/user/project/processor.py
[2023-10-24 10:15:22] [ALERT-NET-01] Outbound connection blocked from /home/user/project/network.py
[2023-10-24 11:42:19] [ALERT-SBX-09] Suspicious activity in /home/user/project/helper.py
[2023-10-24 12:01:05] [ALERT-SBX-09] Suspicious activity in /home/user/project/utils.py
EOF

    chmod -R 777 /home/user

    # Fix specific permissions after the recursive chmod
    chmod 777 /home/user/project/processor.py
    chmod 755 /home/user/project/helper.py
    chmod 666 /home/user/project/network.py
    chmod 777 /home/user/project/utils.py
