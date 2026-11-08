#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc inotify-tools
    pip3 install pytest

    mkdir -p /tmp/staging
    mkdir -p /tmp/build_archive

    # Create dummy files for the payload
    touch /tmp/build_archive/valid_data_1.csv
    touch /tmp/build_archive/valid_data_2.txt

    # Ensure files exist for tar
    touch /var/log/syslog
    touch /etc/passwd

    # Create the nested payload.tar.gz with malicious paths
    # Using -P to allow absolute paths in tar
    cd /tmp/build_archive
    tar -P -czf payload.tar.gz valid_data_1.csv valid_data_2.txt ../../etc/passwd /var/log/syslog
    mv payload.tar.gz /tmp/staging/

    # Create the outer tarball
    cd /tmp/staging
    tar -cf dump.tar payload.tar.gz

    # Split the outer tarball into multi-part archive
    split -b 512 dump.tar dump.tar.

    rm dump.tar payload.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
