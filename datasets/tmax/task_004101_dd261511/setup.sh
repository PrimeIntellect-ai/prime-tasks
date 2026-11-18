#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/datasets/expA/sub_exp
    mkdir -p /home/user/datasets/expB
    mkdir -p /home/user/datasets/broken/chain
    mkdir -p /home/user/compressed
    mkdir -p /home/user/datasets/loopX
    mkdir -p /home/user/datasets/loopY

    echo "Experiment A data sequence 1001" > /home/user/datasets/expA/data1.dat
    echo "Experiment A sub data sequence 1002" > /home/user/datasets/expA/sub_exp/data2.dat
    echo "Experiment B data sequence 2001" > /home/user/datasets/expB/data3.dat
    echo "ignore me" > /home/user/datasets/expA/info.txt

    ln -s /home/user/datasets/broken /home/user/datasets/broken/chain/sym_loop1
    ln -s /home/user/datasets/loopY /home/user/datasets/loopX/to_Y
    ln -s /home/user/datasets/loopX /home/user/datasets/loopY/to_X
    ln -s /home/user/datasets/expB /home/user/datasets/expA/link_to_B

    chmod -R 777 /home/user
