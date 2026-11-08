#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip tar coreutils findutils sed gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/docs_archive/sys/2020
    mkdir -p /home/user/docs_archive/api/v1
    mkdir -p /home/user/docs_archive/guides/misc

    echo "Welcome to the [MACRO:COMPANY_NAME] system docs." | gzip > /home/user/docs_archive/sys/2020/sys_01.txt.gz
    echo "The [MACRO:COMPANY_NAME] API is RESTful." | gzip > /home/user/docs_archive/api/v1/api_auth.txt.gz
    echo "[MACRO:COMPANY_NAME] guide to routing." | gzip > /home/user/docs_archive/guides/misc/guide_route.txt.gz
    echo "Ignore this file, [MACRO:COMPANY_NAME]." | gzip > /home/user/docs_archive/sys/2020/ignore_me.txt.gz

    cat << 'EOF' > /home/user/docs_index.csv
sys_01.txt.gz,System_Overview,introduction
api_auth.txt.gz,API_Reference,authentication
guide_route.txt.gz,User_Guides,routing_setup
EOF

    chmod -R 777 /home/user
