#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/system_mock/bin
    mkdir -p /home/user/system_mock/etc
    mkdir -p /home/user/payload

    # Create files
    echo "good binary data" > /home/user/system_mock/bin/suid_good
    echo "bad binary data" > /home/user/system_mock/bin/suid_honeypot
    echo "good config data" > /home/user/system_mock/etc/ww_good
    echo "bad config data" > /home/user/system_mock/etc/ww_honeypot
    echo "normal binary data" > /home/user/system_mock/bin/normal_good

    # Generate known_hashes.txt for the "good" files only
    rm -f /home/user/known_hashes.txt
    sha256sum /home/user/system_mock/bin/suid_good >> /home/user/known_hashes.txt
    sha256sum /home/user/system_mock/etc/ww_good >> /home/user/known_hashes.txt
    sha256sum /home/user/system_mock/bin/normal_good >> /home/user/known_hashes.txt

    # Modify honeypots silently so their hashes don't match
    echo "tampered" >> /home/user/system_mock/bin/suid_honeypot
    echo "tampered" >> /home/user/system_mock/etc/ww_honeypot

    chmod -R 777 /home/user

    # Set specific permissions after recursive chmod to ensure they are correct
    chmod 4755 /home/user/system_mock/bin/suid_good
    chmod 4755 /home/user/system_mock/bin/suid_honeypot
    chmod 0666 /home/user/system_mock/etc/ww_good
    chmod 0777 /home/user/system_mock/etc/ww_honeypot
    chmod 0755 /home/user/system_mock/bin/normal_good
