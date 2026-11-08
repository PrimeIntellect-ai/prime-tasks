#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset
    cd /home/user/dataset

    # Create normal directories and files
    mkdir -p groupA/sub1 groupA/sub2 groupB/sub1
    touch groupA/sub1/data.csv groupB/sub1/meta.json

    # Create valid symlinks
    ln -s /home/user/dataset/groupA/sub1 /home/user/dataset/groupB/link_to_sub1

    # Create loop 1: Ancestor link
    mkdir -p loop_dir/child/grandchild
    ln -s /home/user/dataset/loop_dir /home/user/dataset/loop_dir/child/grandchild/link_to_ancestor

    # Create loop 2: Mutual recursion
    mkdir -p mutualA mutualB
    ln -s /home/user/dataset/mutualB /home/user/dataset/mutualA/link_to_B
    ln -s /home/user/dataset/mutualA /home/user/dataset/mutualB/link_to_A

    chown -R user:user /home/user/dataset
    chmod -R 777 /home/user
