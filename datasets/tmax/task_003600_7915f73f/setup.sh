#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest

    mkdir -p /home/user/configs/app1
    mkdir -p /home/user/configs/app2/sub
    mkdir -p /home/user/configs/app3
    mkdir -p /home/user/configs/app4

    # Helper to create valid zip
    create_zip() {
        local path=$1
        local version=$2
        local has_meta=$3
        mkdir -p /tmp/zip_gen
        cd /tmp/zip_gen
        rm -f *
        if [ "$has_meta" = "true" ]; then
            echo "{\"version\": \"$version\", \"name\": \"app\"}" > meta.json
            zip -q /tmp/temp.zip meta.json
        else
            echo "dummy data" > dummy.txt
            zip -q /tmp/temp.zip dummy.txt
        fi
        mv /tmp/temp.zip "$path"
        cd - > /dev/null
    }

    # 1. Valid, has meta
    create_zip /home/user/configs/app1/backup.zip "1.2.0" "true"

    # 2. Corrupt
    head -c 100 /dev/urandom > /home/user/configs/app1/old.zip

    # 3. Valid, has meta
    create_zip /home/user/configs/app2/sub/data.zip "2.0.1" "true"

    # 4. Valid, no meta
    create_zip /home/user/configs/app3/sys.zip "3.0.0" "false"

    # 5. Corrupt
    head -c 200 /dev/urandom > /home/user/configs/app4/broken.zip

    # 6. Valid, has meta
    create_zip /home/user/configs/app4/latest.zip "4.5.1" "true"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/configs
    chmod -R 777 /home/user
