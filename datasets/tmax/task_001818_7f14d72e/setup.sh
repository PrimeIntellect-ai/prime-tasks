#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ zip unzip perl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /tmp/doc_setup
    cd /tmp/doc_setup
    echo -n "Welcome to [CONFIDENTIAL_DRAFT] part 1." > raw_01.txt
    echo -n "Advanced routing in [CONFIDENTIAL_DRAFT] part 2." > raw_02.txt
    echo -n "Troubleshooting the [CONFIDENTIAL_DRAFT] system." > raw_03.txt

    # XOR with 0x2F (47 in decimal)
    for i in 1 2 3; do
      cat raw_0$i.txt | perl -pe 's/(.)/chr(ord($1)^0x2F)/sge' > file_0$i.xrd
    done

    zip internal_drafts.zip file_*.xrd
    tar -czf /home/user/old_docs.tar.gz internal_drafts.zip
    rm -rf /tmp/doc_setup

    chmod -R 777 /home/user
