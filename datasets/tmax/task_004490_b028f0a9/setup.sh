#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils
    pip3 install pytest

    mkdir -p /home/user/docs_initial
    cd /home/user/docs_initial

    echo -n "System Architecture Overview" > File_01.TXT
    echo -n "API Endpoint Specification" > draft-02.Txt
    echo -n "User Authentication Flow" > DOC3.text

    echo -n "binary_blob_alpha_9982" | base64 > asset_1.b64
    echo -n "binary_blob_beta_1123" | base64 > image_asset_2.b64

    tar -czf /home/user/docs_archive.tar.gz *
    cd /home/user
    rm -rf /home/user/docs_initial

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
