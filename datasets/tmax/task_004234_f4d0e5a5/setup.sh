#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user

    # Create original files
    echo -e "2023-10-01 10:00:00 INFO Startup\n2023-10-01 10:05:00 WARN Low memory\n2023-10-01 10:10:00 INFO Processing" > project/app.log
    head -c 1024 /dev/urandom > project/data.bin
    head -c 512 /dev/urandom > project/static.bin

    # Create backup_v1
    tar -czf backup_v1.tar.gz -C project app.log data.bin static.bin

    # Modify files in project for the differential state
    echo "2023-10-01 10:15:00 ERROR Out of memory" >> project/app.log
    echo "2023-10-01 10:20:00 INFO Restarting" >> project/app.log
    head -c 1024 /dev/urandom > project/data.bin  # New data.bin content

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
