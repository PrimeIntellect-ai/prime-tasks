#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/configs/subdir
    mkdir -p /home/user/backup

    # Create files with specific modification times
    echo "USER=admin\nPASSWORD=supersecret\nPORT=8080" > /home/user/configs/app1.conf
    touch -m -t 202311150000 /home/user/configs/app1.conf

    echo "USER=guest\nPASSWORD=guessme\nPORT=8081" > /home/user/configs/app2.conf
    touch -m -t 202311100000 /home/user/configs/app2.conf

    echo "DB_HOST=localhost\nPASSWORD=dbpass456\nDB_NAME=test" > /home/user/configs/subdir/app3.conf
    touch -m -t 202311200000 /home/user/configs/subdir/app3.conf

    # Create a symlink loop
    ln -s /home/user/configs /home/user/configs/subdir/loop_link

    # Create the user
    useradd -m -s /bin/bash user || true

    # Fix permissions
    chmod -R 777 /home/user
