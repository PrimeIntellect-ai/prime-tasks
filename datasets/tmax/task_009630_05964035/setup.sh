#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/mem
    mkdir -p /home/user/scripts

    cat << 'EOF' > /home/user/api_deps.txt
user_service billing_engine
auth_gateway user_service
billing_engine report_builder
EOF

    # auth_gateway
    cat << 'EOF' > /home/user/scripts/auth_gateway.emu
READ 0x0010
READ 0x00F4
EOF

    cat << 'EOF' > /home/user/mem/auth_gateway.dump
0x0010 4A
0x0014 FF
0x00F4 39
0x00F8 00
EOF

    # user_service
    cat << 'EOF' > /home/user/scripts/user_service.emu
READ 0x01A0
EOF

    cat << 'EOF' > /home/user/mem/user_service.dump
0x01A0 7B
0x01A4 2C
EOF

    # billing_engine
    cat << 'EOF' > /home/user/scripts/billing_engine.emu
READ 0x1000
EOF

    cat << 'EOF' > /home/user/mem/billing_engine.dump
0x1000 11
0x2000 22
EOF

    # report_builder
    cat << 'EOF' > /home/user/scripts/report_builder.emu
READ 0x0004
EOF

    cat << 'EOF' > /home/user/mem/report_builder.dump
0x0004 9C
0x0008 AA
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
