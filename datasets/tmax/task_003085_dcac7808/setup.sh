#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar unzip zip
    pip3 install pytest

    mkdir -p /home/user/dataset_archives
    mkdir -p /tmp/dataset_build

    # Create .dat files
    for i in $(seq 1 5); do
        cat <<EOF > /tmp/dataset_build/file_0${i}.dat
SENSOR_ID: X${i}
TIMESTAMP: 170000000${i}
Some dummy data for file 0${i}.
EOF
    done

    for i in $(seq 6 9); do
        cat <<EOF > /tmp/dataset_build/file_0${i}.dat
SENSOR_ID: X${i}
TIMESTAMP: 170000000${i}
Some dummy data for file 0${i}.
EOF
    done

    cat <<EOF > /tmp/dataset_build/file_10.dat
SENSOR_ID: X10
TIMESTAMP: 1700000010
Some dummy data for file 10.
EOF

    # Create zip archives
    cd /tmp/dataset_build
    zip batch_A.zip file_01.dat file_02.dat file_03.dat file_04.dat file_05.dat
    zip batch_B.zip file_06.dat file_07.dat file_08.dat file_09.dat file_10.dat

    # Create master tar.gz
    tar -czvf /home/user/dataset_archives/master_dataset.tar.gz batch_A.zip batch_B.zip

    # Cleanup
    rm -rf /tmp/dataset_build

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
