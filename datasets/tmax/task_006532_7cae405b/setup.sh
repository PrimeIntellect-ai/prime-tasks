#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts
    mkdir -p /home/user/staging

    # Create content for archive1
    mkdir -p /tmp/arch1/dir_a
    python3 -c 'print("hello world"[::-1], end="")' > /tmp/arch1/dir_a/file1.cst
    echo -n "normal text file" > /tmp/arch1/normal.txt
    ln -s ../dir_a /tmp/arch1/dir_a/loop_link
    tar -cf /home/user/artifacts/archive1.tar -C /tmp/arch1 .

    # Create content for archive2
    mkdir -p /tmp/arch2/dir_b
    python3 -c 'print("secret data payload"[::-1], end="")' > /tmp/arch2/dir_b/file2.cst
    ln -s /tmp/arch2/dir_b /tmp/arch2/dir_b/infinite_loop
    tar -cf /home/user/artifacts/archive2.tar -C /tmp/arch2 .

    # Create corrupt archive3
    echo "This is not a valid tar file" > /home/user/artifacts/archive3.tar

    chmod -R 777 /home/user
