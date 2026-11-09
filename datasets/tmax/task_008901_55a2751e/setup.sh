#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset/group_alpha
    mkdir -p /home/user/dataset/group_beta

    # Create the symlink loop
    ln -s /home/user/dataset /home/user/dataset/group_alpha/loop_link

    # Create data files
    cat << 'EOF' > /home/user/dataset/group_alpha/sensor1.dat
##RAW_DATA - DO NOT PARSE
101|5.45|2023-10-01T10:00:00Z
INVALID_ROW
102|5.46|2023-10-01T10:01:00Z
EOF

    cat << 'EOF' > /home/user/dataset/group_beta/sensor2.dat
##RAW_DATA V2.1
103|9.12|2023-10-01T10:02:00Z
104|9.15|2023-10-01T10:03:00Z
INVALID_ROW
EOF

    cat << 'EOF' > /home/user/dataset/group_beta/sensor3.dat
##RAW_DATA
INVALID_ROW
105|7.77|2023-10-01T10:04:00Z
EOF

    chmod -R 777 /home/user
