#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
[2023/05/12] [INFO] <aBcD1234> - User Logged In
[2023-05-12] [INFO] <aBcD1234> - Wrong date format
[2023/08/22] [ERROR] <XyZ98765> - DATABASE CONNECTION FAILED
[2023/05/13] [DEBUG] <aBcD1235> - Invalid level
[2023/05/14] [WARN] <short> - Short ID
[2023/05/15] [INFO] <aBcD12345> - Long ID
2023/05/16 [INFO] <aBcD1234> - Missing brackets
[2023/01/01] [WARN] <11112222> - High CPU usage detected
[2023/12/31] [ERROR] <AbCdEfGh> - FATAL crash
[9999/99/99] [INFO] <00000000> - Just valid enough for regex
EOF

    chmod -R 777 /home/user
