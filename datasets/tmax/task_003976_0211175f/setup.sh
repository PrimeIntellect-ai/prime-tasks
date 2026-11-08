#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar g++
    pip3 install pytest

    mkdir -p /home/user/raw_docs
    cd /home/user/raw_docs

    # Create files for zip 1
    echo "Content of Alpha" > guide_alpha.md
    echo "Content of Delta" > guide_delta.md
    zip part1.zip guide_alpha.md guide_delta.md
    rm guide_alpha.md guide_delta.md

    # Create files for zip 2
    echo "Content of Beta" > guide_beta.md
    echo "Content of Gamma" > guide_gamma.md
    zip part2.zip guide_beta.md guide_gamma.md
    rm guide_beta.md guide_gamma.md

    cd /home/user
    tar -czf docs_incoming.tar.gz raw_docs/
    rm -rf raw_docs/

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
