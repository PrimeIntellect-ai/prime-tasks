#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/artifacts/v1.0
    mkdir -p /home/user/artifacts/v2.0/sub_module

    echo -n "binary_data_1" > /home/user/artifacts/v1.0/app_v1.bin
    echo '{"name": "AppCore", "version": "1.0"}' > /home/user/artifacts/v1.0/app_v1.json

    echo -n "binary_data_2" > /home/user/artifacts/v2.0/app_v2.bin
    echo '{"name": "AppCore", "version": "2.0"}' > /home/user/artifacts/v2.0/app_v2.json

    echo -n "binary_data_3" > /home/user/artifacts/v2.0/sub_module/helper.bin
    echo '{"name": "HelperTool", "version": "1.1"}' > /home/user/artifacts/v2.0/sub_module/helper.json

    ln -s /home/user/artifacts/v2.0 /home/user/artifacts/latest
    ln -s /home/user/artifacts /home/user/artifacts/v2.0/legacy_loop

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
