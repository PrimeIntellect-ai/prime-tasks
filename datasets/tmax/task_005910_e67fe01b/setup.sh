#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev tar gzip
    pip3 install pytest

    mkdir -p /home/user/legacy_docs/guides/getting_started
    mkdir -p /home/user/legacy_docs/api/v1
    mkdir -p /home/user/legacy_docs/api/v2
    mkdir -p /home/user/legacy_docs/tutorials/basics

    echo "setup content" > /home/user/legacy_docs/guides/getting_started/setup_inst.txt
    echo "old api content" > /home/user/legacy_docs/api/v1/auth_endpoints.txt
    echo "new api content" > /home/user/legacy_docs/api/v2/auth_v2.txt
    echo "loop content" > /home/user/legacy_docs/tutorials/basics/loops.txt
    echo "draft content" > /home/user/legacy_docs/tutorials/basics/variables.txt
    echo "unlisted content" > /home/user/legacy_docs/guides/unlisted.txt

    cd /home/user
    tar -czf legacy_docs.tar.gz legacy_docs
    rm -rf legacy_docs

    cat << 'EOF' > /home/user/doc_index.csv
original_filename,new_filename,section,status
setup_inst.txt,installation_guide,guides,approved
auth_endpoints.txt,authentication_v1,api,deprecated
auth_v2.txt,authentication_v2,api,approved
loops.txt,for_loops_tutorial,tutorials,approved
variables.txt,variables_tutorial,tutorials,draft
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
