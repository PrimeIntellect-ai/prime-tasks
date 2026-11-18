#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data/set_A
    mkdir -p /home/user/raw_data/set_B

    # Create regular files with mixed content
    cat << 'EOF' > /home/user/raw_data/set_A/file1.dat
[RETAIN] data_point_1
[DROP] invalid_data
[RETAIN] data_point_7
EOF

    cat << 'EOF' > /home/user/raw_data/set_B/file2.dat
[DROP] nothing_here
[RETAIN] data_point_2
[RETAIN] data_point_5
EOF

    # Create a symlink loop
    ln -s /home/user/raw_data/set_B /home/user/raw_data/set_A/loop_dir
    ln -s /home/user/raw_data/set_A /home/user/raw_data/set_B/loop_dir

    # Set ownership and permissions
    chown -R user:user /home/user/raw_data
    chmod -R 777 /home/user
