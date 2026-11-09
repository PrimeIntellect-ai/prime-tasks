#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest

    mkdir -p /home/user/research_setup
    cd /home/user/research_setup

    # Chunk 1
    mkdir chunk1
    echo '{"sensor_id": "alpha"}' > chunk1/metadata.json
    echo -e "timestamp,reading\n1,10.0\n2,20.0\n3,30.0" > chunk1/data.csv
    tar -czf chunk1.tar.gz -C chunk1 .

    # Chunk 2
    mkdir chunk2
    echo '{"sensor_id": "beta"}' > chunk2/metadata.json
    echo -e "timestamp,reading\n1,5.5\n2,15.5\n3,10.0" > chunk2/data.csv
    tar -czf chunk2.tar.gz -C chunk2 .

    # Chunk 3
    mkdir chunk3
    echo '{"sensor_id": "gamma"}' > chunk3/metadata.json
    echo -e "timestamp,reading\n1,100.0\n2,-50.0" > chunk3/data.csv
    tar -czf chunk3.tar.gz -C chunk3 .

    zip /home/user/research_data.zip chunk1.tar.gz chunk2.tar.gz chunk3.tar.gz

    cd /home/user
    rm -rf /home/user/research_setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
