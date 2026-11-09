#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    echo -e "127.0.0.1:9001\n127.0.0.1:9002\n127.0.0.1:9003" > /home/user/backends.txt
    touch /home/user/diagnostics.log

    chown -R user:user /home/user
    chmod -R 777 /home/user
