#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/reports/

    # Create binary garbage files
    dd if=/dev/urandom of=/home/user/reports/garbage1.bin bs=1M count=2
    dd if=/dev/urandom of=/home/user/reports/garbage2.bin bs=1M count=5

    # Create .dat files with different encodings using python to ensure exact match with tests
    python3 -c "open('/home/user/reports/vol_alpha.dat', 'wb').write('VOLUME:ALPHA|USAGE:1024'.encode('utf-16le'))"
    python3 -c "open('/home/user/reports/vol_beta.dat', 'wb').write('VOLUME:BETA|USAGE:2048'.encode('iso-8859-1'))"
    python3 -c "open('/home/user/reports/vol_gamma.dat', 'wb').write('VOLUME:GAMMA|USAGE:512'.encode('utf-8'))"

    chmod -R 777 /home/user
