#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/project_a
    mkdir -p /home/user/data/project_b
    mkdir -p /home/user/data/project_c
    mkdir -p /home/user/nginx_run

    cat << 'EOF' > /home/user/cost_fstab
/home/user/data/project_a  nfs  defaults,tier=expensive 0 0
/home/user/data/project_b  ext4 defaults,tier=cheap 0 0
/home/user/data/project_c  nfs  defaults,tier=expensive 0 0
EOF

    dd if=/dev/zero of=/home/user/data/project_a/file1.dat bs=1024 count=60
    dd if=/dev/zero of=/home/user/data/project_c/file2.dat bs=1024 count=60
    dd if=/dev/zero of=/home/user/data/project_b/file3.dat bs=1024 count=200

    chmod -R 777 /home/user
