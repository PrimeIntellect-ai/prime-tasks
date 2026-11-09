#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create directory structure
    mkdir -p /home/user/raw_data/session1
    mkdir -p /home/user/raw_data/session2/subset
    mkdir -p /home/user/raw_data/session3/logs

    # Create target CSV files with exact literal content (including literal \n)
    echo -n 'timestamp,value,status\n1600000000,42.5,OK' > /home/user/raw_data/session1/sensorA.csv
    echo -n 'timestamp,value,status\n1600000010,43.1,WARN' > /home/user/raw_data/session2/subset/sensorB.csv
    echo -n 'timestamp,value,status\n1600000020,0.0,ERR' > /home/user/raw_data/session3/logs/sensorC.csv

    # Create distractor files
    echo -n "junk data" > /home/user/raw_data/session1/cache.tmp
    echo -n "image data fake" > /home/user/raw_data/session2/subset/photo.jpg

    # Ensure correct permissions
    chmod -R 777 /home/user
