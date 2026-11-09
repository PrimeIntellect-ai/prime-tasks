#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/raw_logs

    cat << 'EOF' > /home/user/raw_logs/auth.log
2023/10/01 10:00:00 | T100 | SUCCESS
2023/10/01 10:00:05 | T101 | FAIL
2023/10/01 10:00:10 | T102 | SUCCESS
EOF

    cat << 'EOF' > /home/user/raw_logs/db.log
1696154402 | T100 | 45
1696154406 | T101 | 120
1696154403 | T100 | 30
1696154415 | T102 | 200
EOF

    cat << 'EOF' > /home/user/raw_logs/api.log
2023-10-01T10:00:01Z | T100 | /users | 200
2023-10-01T10:00:07Z | T101 | /checkout | 500
2023-10-01T10:00:11Z | T102 | /process | 201
2023-10-01T10:00:16Z | T102 | /confirm | 200
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
