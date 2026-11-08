#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_docs/folderA
    mkdir -p /home/user/legacy_docs/folderB/subfolder

    # Create file 1: UTF-8
    echo "Welcome to AcmeCorp. AcmeCorp provides the best anvils." > /home/user/legacy_docs/folderA/file1.txt

    # Create file 2: UTF-16LE
    echo "AcmeCorp rockets are reliable. Contact AcmeCorp support." | iconv -f UTF-8 -t UTF-16LE > /home/user/legacy_docs/folderB/file2.txt

    # Create file 3: ISO-8859-1
    echo "Copyright 2003 AcmeCorp. All rights reserved by AcmeCorp." | iconv -f UTF-8 -t ISO-8859-1 > /home/user/legacy_docs/folderB/subfolder/file3.txt

    # Create a symlink to a file
    ln -s /home/user/legacy_docs/folderA/file1.txt /home/user/legacy_docs/link_file.txt

    # Create infinite symlink loops
    ln -s /home/user/legacy_docs /home/user/legacy_docs/folderA/loop_back
    ln -s /home/user/legacy_docs/folderB /home/user/legacy_docs/folderB/subfolder/loop_b

    chown -R user:user /home/user/legacy_docs
    chmod -R 777 /home/user
