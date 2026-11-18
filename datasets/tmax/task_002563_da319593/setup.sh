#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils findutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data
    cd /home/user/raw_data

    # Create text files with ISO-8859-1 encoding and spaces in names
    echo -n "Café observation data: 42" | iconv -f UTF-8 -t ISO-8859-1 > "cafe log 1.txt"
    echo -n "München research group notes" | iconv -f UTF-8 -t ISO-8859-1 > "group notes 2.txt"

    # Create a symlink loop
    ln -s . "infinite_loop_link"

    # Create the archive
    cd /home/user
    tar -cf research_data.tar -C raw_data .
    rm -rf /home/user/raw_data

    chmod -R 777 /home/user
