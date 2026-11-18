#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/math_nodes

    echo -n "B,C" > /home/user/math_nodes/A.txt
    echo -n "D" > /home/user/math_nodes/B.txt
    echo -n "D,E" > /home/user/math_nodes/C.txt
    touch /home/user/math_nodes/D.txt
    touch /home/user/math_nodes/E.txt

    chmod -R 777 /home/user
