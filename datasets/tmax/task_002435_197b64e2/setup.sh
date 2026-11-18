#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils sed findutils
    pip3 install pytest

    mkdir -p /home/user/raw_dataset
    cd /home/user/raw_dataset

    # Create symlink loop
    mkdir -p dirA dirB
    ln -s ../dirB dirA/link_to_B
    ln -s ../dirA dirB/link_to_A

    # Create .dat files with predictable content
    # file1.dat
    cat << 'EOF' > file1.dat
INFO 2023/01/01 Starting sequence A
DEBUG 2023/01/01 Loading modules
ERROR 2023/01/02 Module load failed
INFO 2023/01/02 Retrying sequence A
INFO 2023/01/03 Sequence A complete
EOF

    for i in {1..40}; do
        echo "INFO 2023/02/01 Data point A$i" >> file1.dat
    done

    # file2.dat inside dirA
    cat << 'EOF' > dirA/file2.dat
INFO 2023/03/01 Starting sequence B
ERROR 2023/03/01 Critical failure
INFO 2023/03/02 Recovered sequence B
EOF

    for i in {1..30}; do
        echo "INFO 2023/03/05 Data point B$i" >> dirA/file2.dat
    done

    # file3.dat inside dirB
    cat << 'EOF' > dirB/file3.dat
DEBUG 2023/04/01 Heartbeat check
INFO 2023/04/02 System stable
EOF

    for i in {1..45}; do
        echo "INFO 2023/04/10 Data point C$i" >> dirB/file3.dat
    done

    # Tar the dataset
    cd /home/user
    tar -czf raw_data.tar.gz -C raw_dataset .
    rm -rf raw_dataset

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
