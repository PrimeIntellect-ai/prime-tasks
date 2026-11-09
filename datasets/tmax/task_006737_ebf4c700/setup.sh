#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang-go
    pip3 install pytest

    mkdir -p /home/user/release_prep/data
    cd /home/user/release_prep/data

    # Test 1
    printf "1\n3\n5\n" > a1.txt
    printf "2\n4\n6\n" > b1.txt
    printf "1\n2\n3\n4\n5\n6\n" > exp1.txt

    # Test 2
    printf "10\n20\n" > a2.txt
    printf "5\n15\n" > b2.txt
    printf "5\n10\n15\n20\n" > exp2.txt

    # Test 3
    touch a3.txt
    printf "1\n" > b3.txt
    printf "1\n" > exp3.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
