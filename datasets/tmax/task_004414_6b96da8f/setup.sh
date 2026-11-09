#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/docs_input
    mkdir -p /home/user/docs_output

    # Create directories
    mkdir -p /home/user/docs_input/module_a
    mkdir -p /home/user/docs_input/module_b/submodule
    mkdir -p /home/user/docs_input/module_c

    # Create text files
    echo -n "AAAAABBBBBCCCCC" > /home/user/docs_input/module_a/intro.txt
    echo -n "DDDDDEEEEEFFFFF" > /home/user/docs_input/module_b/submodule/details.txt

    # File with > 255 chars to test RLE splitting
    python3 -c "print('G'*300, end='')" > /home/user/docs_input/module_c/long.txt

    # Create valid symlinks
    ln -s /home/user/docs_input/module_a/intro.txt /home/user/docs_input/module_c/intro_link.txt
    ln -s /home/user/docs_input/module_b/submodule/details.txt /home/user/docs_input/module_a/details_link.txt

    # Create infinite loop symlinks
    ln -s /home/user/docs_input/module_a /home/user/docs_input/module_a/loop_dir
    ln -s /home/user/docs_input/module_b /home/user/docs_input/module_b/submodule/loop_back

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
