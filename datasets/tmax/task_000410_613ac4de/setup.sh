#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/quarantine
    mkdir -p /home/user/app_data

    echo '{"base_dir": "/home/user/app_data"}' > /home/user/config.json

    cat << 'EOF' > /home/user/extraction.log
Record ID: 101
Path: /home/user/app_data/docs/readme.txt
Size: 15

Record ID: 102
Path: /home/user/app_data/docs/../../.ssh/id_rsa
Size: 17

Record ID: 103
Path: /home/user/app_data/images/logo.png
Size: 13

Record ID: 104
Path: /home/user/app_data/../app_data_backup/secret.key
Size: 17

Record ID: 105
Path: /home/user/app_data/./config/settings.ini
Size: 20
EOF

    echo "readme content" > /home/user/quarantine/101.dat
    echo "fake private key" > /home/user/quarantine/102.dat
    echo "logo content" > /home/user/quarantine/103.dat
    echo "secret key value" > /home/user/quarantine/104.dat
    echo "settings config" > /home/user/quarantine/105.dat

    chmod -R 777 /home/user
