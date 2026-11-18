#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    mkdir -p /home/user/incoming
    mkdir -p /home/user/tmp_setup
    cd /home/user/tmp_setup

    echo "alpha binary payload" > alpha.bin
    echo "beta binary payload data" > beta.bin
    echo "gamma binary payload information" > gamma.bin
    echo "delta binary payload test" > delta.bin
    echo "ignore me" > ignore.txt

    zip -q group1.zip alpha.bin beta.bin ignore.txt
    zip -q group2.zip gamma.bin delta.bin

    tar -cf /home/user/incoming/payload.tar group1.zip group2.zip

    cd /home/user
    rm -rf /home/user/tmp_setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
