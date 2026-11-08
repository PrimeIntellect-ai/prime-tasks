#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/archive/temp_docs
    cd /home/user/archive
    for i in $(seq -w 1 100); do
        echo "This is document $i for AcmeCorp. Welcome to AcmeCorp." > temp_docs/doc_${i}.md
        echo "AcmeCorp provides excellent solutions." >> temp_docs/doc_${i}.md
    done
    tar -cf legacy_docs.tar -C temp_docs .
    gzip legacy_docs.tar
    rm -rf temp_docs

    chmod -R 777 /home/user
