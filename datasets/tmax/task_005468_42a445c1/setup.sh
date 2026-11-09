#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/project_alpha /home/user/project_beta

    echo -n "AAAAABBBCC" > /home/user/project_alpha/file1.txt
    echo -n "Hello World!" > /home/user/project_beta/file2.txt

    ln -s /home/user/project_alpha /home/user/project_alpha/loop_link
    ln -s /home/user/project_alpha /home/user/project_beta/link_to_alpha
    ln -s /home/user/project_beta/file2.txt /home/user/project_alpha/file2_link.txt

    cat <<EOF > /home/user/archive.conf
/home/user/project_alpha
/home/user/project_beta
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
