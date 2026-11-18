#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs

    cat << 'EOF' > /home/user/configs/a_init.conf
SERVER_PORT=8080
DB_HOST=localhost
WELCOME_MSG=Hello World
EOF

    cat << 'EOF' > /home/user/configs/b_update.conf
SERVER_PORT=9000
MAX_CONN=100
GREETING=¡Hola Mundo!
EOF

    cat << 'EOF' > /home/user/configs/c_invalid.conf
INVALID-KEY=123
DB_HOST=remote
EOF

    cat << 'EOF' > /home/user/configs/d_override.conf
MAX_CONN=500
DB_PASS=S3cr3t
EOF

    cat << 'EOF' > /home/user/configs/e_bad_value.conf
NEW_KEY=ValidValue
BAD_VALUE=Has
Newline
EOF

    chmod -R 777 /home/user
