#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang zip unzip tar
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Setup the task environment
    mkdir -p /home/user/setup_dir
    cp /bin/ls /home/user/setup_dir/sys_ls
    cp /bin/cat /home/user/setup_dir/sys_cat
    echo "This is just a text file, not an ELF." > /home/user/setup_dir/notes.txt
    cd /home/user/setup_dir
    zip inner.zip sys_ls sys_cat notes.txt
    tar -czvf /home/user/project_files.tar.gz inner.zip
    cd /home/user
    rm -rf /home/user/setup_dir

    # Set permissions
    chmod -R 777 /home/user
