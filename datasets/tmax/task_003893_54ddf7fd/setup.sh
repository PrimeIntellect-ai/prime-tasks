#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/project_files/module1
    mkdir -p /home/user/project_files/module2/submodule

    # Create files
    echo -n "AAAAABBBBBCCCCC" > /home/user/project_files/fileA.txt
    echo -n "hellooo worlddd" > /home/user/project_files/module1/fileB.txt
    printf "line111\nline222\n" > /home/user/project_files/module2/submodule/fileC.txt

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
