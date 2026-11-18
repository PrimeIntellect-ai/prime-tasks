#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_mount/projects
    mkdir -p /home/user/data_mount/users/alice
    mkdir -p /home/user/data_mount/users/bob

    # Create a valid zip > 50KB, old
    dd if=/dev/urandom of=/tmp/dummy1 bs=1K count=100 2>/dev/null
    zip -j /home/user/data_mount/projects/valid_old.zip /tmp/dummy1 >/dev/null
    touch -d "40 days ago" /home/user/data_mount/projects/valid_old.zip

    # Create a valid tar.gz > 50KB, old
    tar -czf /home/user/data_mount/users/alice/valid_old.tar.gz -C /tmp dummy1
    touch -d "35 days ago" /home/user/data_mount/users/alice/valid_old.tar.gz

    # Create a corrupted zip > 50KB, old
    cp /home/user/data_mount/projects/valid_old.zip /home/user/data_mount/users/bob/corrupt_old.zip
    # Corrupt it by truncating
    truncate -s 60K /home/user/data_mount/users/bob/corrupt_old.zip
    touch -d "50 days ago" /home/user/data_mount/users/bob/corrupt_old.zip

    # Create a corrupted tar.gz > 50KB, old
    cp /home/user/data_mount/users/alice/valid_old.tar.gz /home/user/data_mount/projects/corrupt_old.tar.gz
    # Corrupt it by overwriting part of it
    dd if=/dev/zero of=/home/user/data_mount/projects/corrupt_old.tar.gz bs=1K count=10 conv=notrunc 2>/dev/null
    touch -d "60 days ago" /home/user/data_mount/projects/corrupt_old.tar.gz

    # Create a valid zip > 50KB, RECENT (should be ignored)
    zip -j /home/user/data_mount/users/alice/valid_recent.zip /tmp/dummy1 >/dev/null
    touch -d "2 days ago" /home/user/data_mount/users/alice/valid_recent.zip

    # Create a valid zip < 50KB, old (should be ignored)
    dd if=/dev/urandom of=/tmp/dummy2 bs=1K count=20 2>/dev/null
    zip -j /home/user/data_mount/projects/small_old.zip /tmp/dummy2 >/dev/null
    touch -d "40 days ago" /home/user/data_mount/projects/small_old.zip

    # Create symlinks
    ln -s /home/user/data_mount/projects/valid_old.zip /home/user/data_mount/users/bob/link_to_valid.zip
    ln -s /home/user/data_mount/projects/corrupt_old.tar.gz /home/user/data_mount/users/alice/link_to_corrupt.tar.gz

    rm /tmp/dummy1 /tmp/dummy2

    chmod -R 777 /home/user
