#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/datasets_raw/exp1
    mkdir -p /home/user/datasets_raw/exp2/logs

    # Create files with deterministic content
    printf "id,val\n1,10\n2,20\n" > /home/user/datasets_raw/exp1/results.csv
    printf '{"env": "test"}' > /home/user/datasets_raw/exp1/config.json
    printf "started\nfinished\n" > /home/user/datasets_raw/exp1/run.log

    printf "a,b,c\nx,y,z\n" > /home/user/datasets_raw/exp2/data.csv
    printf "12345" > /home/user/datasets_raw/exp2/temp.tmp

    printf "Analyze exp2 soon." > /home/user/datasets_raw/notes.txt
    printf '{"total": 2}' > /home/user/datasets_raw/summary.json

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
