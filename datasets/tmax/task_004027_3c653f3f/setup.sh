#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc coreutils
    pip3 install pytest

    mkdir -p /home/user/project_data/docs /home/user/project_data/assets /home/user/project_data/src

    echo -n "Important documentation" > /home/user/project_data/docs/readme.txt
    echo -n "fn main() { println!(\"Hello\"); }" > /home/user/project_data/src/main.rs
    dd if=/dev/urandom of=/home/user/project_data/assets/blob.bin bs=1K count=4 2>/dev/null

    ln -s /home/user/project_data /home/user/project_data/docs/loop_to_root
    ln -s /home/user/project_data/docs /home/user/project_data/assets/loop_to_docs
    ln -s /home/user/project_data/src/main.rs /home/user/project_data/docs/main_link.rs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
