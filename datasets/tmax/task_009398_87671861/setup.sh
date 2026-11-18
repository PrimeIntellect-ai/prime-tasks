#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev coreutils findutils
    pip3 install pytest

    mkdir -p /home/user/docs/part1 /home/user/docs/part2
    echo -n "2T1e1s2t" > /home/user/docs/part1/docA.rld
    echo -n "1M1a1s1t1e1r" > /home/user/docs/part2/docB.rld
    echo -n "4F1A1I1L" > /home/user/docs/part1/docC.rld
    touch -d "10 days ago" /home/user/docs/part1/docC.rld

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
