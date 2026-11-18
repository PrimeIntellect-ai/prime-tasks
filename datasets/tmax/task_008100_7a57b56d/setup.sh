#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    mkdir -p /home/user/legacy_docs
    mkdir -p /home/user/legacy_docs/guides
    mkdir -p /home/user/legacy_docs/api

    echo "Welcome to <macro: old_version>." > "/home/user/legacy_docs/Intro Guide.DOC"
    echo "API details for <macro: old_version> here." > "/home/user/legacy_docs/api/REST Spec.DOC"
    echo "No macros here." > "/home/user/legacy_docs/guides/Setup.DOC"

    # Create infinite symlink loop
    ln -s . /home/user/legacy_docs/infinite_loop
    ln -s ../guides /home/user/legacy_docs/api/recursive_guides

    # Create tarball
    cd /home/user
    tar -czvf legacy_docs.tar.gz legacy_docs
    rm -rf legacy_docs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
