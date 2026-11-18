#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/staging
    cd /home/user/staging

    # Create mock legacy code A
    mkdir -p projectA/utils
    # "café" in ISO-8859-1
    echo -ne 'caf\xe9\n' > projectA/main.src
    # "résumé" in ISO-8859-1
    echo -ne 'r\xe9sum\xe9\n' > projectA/utils/helper.src
    # normal txt
    echo "README" > projectA/readme.txt
    tar -czf legacy_code_A.tar.gz projectA/
    rm -rf projectA/

    # Create mock legacy code B
    mkdir -p moduleB
    # "niño" in ISO-8859-1
    echo -ne 'ni\xf1o\n' > moduleB/app.src
    tar -czf legacy_code_B.tar.gz moduleB/
    rm -rf moduleB/

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
