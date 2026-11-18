#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/messy_project/src/core
    mkdir -p /home/user/messy_project/lib/utils
    mkdir -p /home/user/messy_project/docs

    # Create text files
    echo "This is a clean note." > /home/user/messy_project/docs/note1.txt
    echo "TODO: refactor the core module." > /home/user/messy_project/docs/note2.txt
    echo "Another TODO item here." > /home/user/messy_project/src/todo_list.txt

    # Create Python files
    seq 1 30 | awk '{print "print(\"Helper line " $1 "\")"}' > /home/user/messy_project/lib/utils/helper.py
    seq 1 60 | awk '{print "print(\"Main line " $1 "\")"}' > /home/user/messy_project/src/core/main.py
    seq 1 25 | awk '{print "print(\"App line " $1 "\")"}' > /home/user/messy_project/src/app.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
