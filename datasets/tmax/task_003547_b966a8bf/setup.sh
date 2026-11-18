#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip util-linux
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
LOG-001:PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==
LOG-002:U0VMRUNUICogRlJPTSB1c2Vyczs=
LOG-003:JyBPUiAxPTEgLS0=
LOG-004:aGVsbG8gd29ybGQ=
LOG-005:PGltZyBzcmM9eCBvbmVycm9yPWFsZXJ0KDEpPg==
LOG-006:VU5JT04gU0VMRUNUIHVzZXJuYW1lLCBwYXNzd29yZCBGUk9NIGFkbWlucw==
EOF

    chmod -R 777 /home/user
