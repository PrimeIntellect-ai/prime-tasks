#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/docs_draft
    mkdir -p /home/user/releases

    echo "Title: Document 1" > /home/user/docs_draft/doc1.md
    echo "Title: Document 2" > /home/user/docs_draft/doc2.md
    echo "binarydata_img1" > /home/user/docs_draft/img1.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
