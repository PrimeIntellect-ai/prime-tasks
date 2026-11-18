#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential zip tar cargo rustc
    pip3 install pytest

    mkdir -p /home/user/setup_temp
    cd /home/user/setup_temp

    # File 1: ID 1001, contains an e-acute in ISO-8859-1 (\xE9)
    echo -ne "ARCHIVE-ID: 1001\nSystem status: \xE9chou\xE9\n" > legacy_1.log

    # File 2: ID 2005, contains a degree symbol in ISO-8859-1 (\xB0)
    echo -ne "ARCHIVE-ID: 2005\nTemperature: 45\xB0C\n" > legacy_2.log

    # File 3: ID 99X3, contains an a-umlaut in ISO-8859-1 (\xE4)
    echo -ne "ARCHIVE-ID: 99X3\nUser: m\xE4dchen\n" > legacy_3.log

    # Create intermediate zips
    zip -j part1.zip legacy_1.log legacy_2.log
    zip -j part2.zip legacy_3.log

    # Create final tarball
    tar -czf /home/user/legacy_backups.tar.gz part1.zip part2.zip

    # Cleanup
    cd /home/user
    rm -rf /home/user/setup_temp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
