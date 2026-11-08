#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/archives/

    # File 1: v1
    echo 'DATAv1.0' | tr -d '\n' > /home/user/archives/data1.dat
    echo '{"sensor": "A", "val": 10}' | gzip -c >> /home/user/archives/data1.dat

    # File 2: v2
    echo 'DATAv2.0' | tr -d '\n' > /home/user/archives/data2.dat
    echo '{"sensor": "B", "val": 20}\n{"sensor": "B", "val": 21}' | gzip -c >> /home/user/archives/data2.dat

    # File 3: v2
    echo 'DATAv2.0' | tr -d '\n' > /home/user/archives/data3.dat
    echo '{"sensor": "C", "val": 30}\n{"sensor": "C", "val": 31}\n{"sensor": "C", "val": 32}' | gzip -c >> /home/user/archives/data3.dat

    # File 4: v1
    echo 'DATAv1.0' | tr -d '\n' > /home/user/archives/data4.dat
    echo '{"sensor": "D", "val": 40}' | gzip -c >> /home/user/archives/data4.dat

    # File 5: v2
    echo 'DATAv2.0' | tr -d '\n' > /home/user/archives/data5.dat
    echo '{"sensor": "E", "val": 50}' | gzip -c >> /home/user/archives/data5.dat

    chmod -R 777 /home/user
