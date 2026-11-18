#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk util-linux coreutils
    pip3 install pytest

    mkdir -p /home/user/configs

    # Create config files
    echo "db_host=localhost" > /home/user/configs/db.conf
    echo "db_port=5432" >> /home/user/configs/db.conf

    echo "web_port=8080" > /home/user/configs/web.conf
    echo "web_workers=4" >> /home/user/configs/web.conf

    echo "cache_size=1024" > /home/user/configs/cache.conf

    # Create old manifest simulating an older state
    DB_SUM=$(sha256sum /home/user/configs/db.conf | awk '{print $1}')
    echo "$DB_SUM  /home/user/configs/db.conf" > /home/user/old_manifest.txt
    echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  /home/user/configs/web.conf" >> /home/user/old_manifest.txt

    # Create symlink loops to trap naive traversal
    ln -s /home/user/configs/loop2 /home/user/configs/loop1
    ln -s /home/user/configs/loop1 /home/user/configs/loop2
    ln -s /home/user/configs /home/user/configs/self_link

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
