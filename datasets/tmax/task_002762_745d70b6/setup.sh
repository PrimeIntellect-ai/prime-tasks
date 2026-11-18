#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/archive_mess
    cd /home/user/archive_mess

    # Create dummy logs
    mkdir -p tmp/zips

    # Set 1
    echo "All systems normal" > tmp/app1.txt
    echo "2023-10-05 - Warning: Low memory" >> tmp/app1.txt
    echo "2023-10-05 - ERROR_STATE_RACE_CONDITION in db_lock" > tmp/app2.txt
    echo "Connection closed" >> tmp/app2.txt

    cd tmp
    zip zips/logsA.zip app1.txt app2.txt
    cd ..

    # Set 2
    echo "2023-10-06 - ERROR_STATE_RACE_CONDITION during cache flush" > tmp/app3.txt
    echo "Restarting service..." >> tmp/app3.txt
    echo "All good here" > tmp/app4.txt

    cd tmp
    zip zips/logsB.zip app3.txt app4.txt
    cd ..

    # Tar them up
    cd tmp/zips
    tar -cvf ../../bundle1.tar logsA.zip
    tar -cvf ../../bundle2.tar logsB.zip
    cd ../..

    # Cleanup tmp
    rm -rf tmp

    chmod -R 777 /home/user
