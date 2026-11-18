#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    mkdir -p /home/user/project_data/fragments
    mkdir -p /home/user/project_data/loop_a
    mkdir -p /home/user/project_data/loop_b

    # Create an infinite symlink loop
    ln -s /home/user/project_data/loop_b /home/user/project_data/loop_a/link_to_b
    ln -s /home/user/project_data/loop_a /home/user/project_data/loop_b/link_to_a

    # Create the reference binary file (2.5 MB)
    dd if=/dev/urandom of=/home/user/project_data/reference.bin bs=1024 count=2560 status=none

    # Split it into fragments (5 fragments of 512KB)
    split -b 524288 /home/user/project_data/reference.bin /tmp/frag_
    mv /tmp/frag_aa /home/user/project_data/fragments/part_1.bin
    mv /tmp/frag_ab /home/user/project_data/fragments/part_2.bin
    mv /tmp/frag_ac /home/user/project_data/fragments/part_3.bin
    mv /tmp/frag_ad /home/user/project_data/fragments/part_4.bin
    mv /tmp/frag_ae /home/user/project_data/fragments/part_5.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
