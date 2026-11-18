#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tar gzip
    pip3 install pytest

    mkdir -p /home/user/docs/api /home/user/docs/guides
    echo "Welcome to the docs. %% AUTHOR : Alice%% %% DATE :  2020-01-01 %%" > /home/user/docs/intro.txt
    echo "API V1. %%AUTHOR:Bob%% %%DATE:2021-05-12%%" > /home/user/docs/api/v1.txt
    echo "API V2. %%  AUTHOR : Charlie  %% %% DATE:2022-10-10%%" > /home/user/docs/api/v2.txt
    echo "Guide 1. %%AUTHOR: Dave%%" > /home/user/docs/guides/guide1.txt
    cd /home/user
    tar -czf legacy_docs.tar.gz docs/
    rm -rf docs/

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
