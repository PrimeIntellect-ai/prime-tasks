#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip file tar coreutils libc-bin
    pip3 install pytest

    mkdir -p /home/user/source_project/docs
    mkdir -p /home/user/source_project/src

    # Create text files in ISO-8859-1
    echo "El pingüino y el niño" | iconv -f UTF-8 -t ISO-8859-1 > /home/user/source_project/docs/story1.txt
    echo "Más camaleón" | iconv -f UTF-8 -t ISO-8859-1 > /home/user/source_project/docs/story2.txt

    # Create duplicate files
    echo "id,name,value" > /home/user/source_project/src/data.csv
    echo "1,alpha,100" >> /home/user/source_project/src/data.csv
    echo "2,beta,200" >> /home/user/source_project/src/data.csv

    cp /home/user/source_project/src/data.csv /home/user/source_project/src/data_backup.csv
    cp /home/user/source_project/src/data.csv /home/user/source_project/docs/data_copy.csv

    # Create archive
    cd /home/user/source_project
    tar -czf /home/user/incoming_project.tar.gz .
    cd /home/user
    rm -rf /home/user/source_project

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
