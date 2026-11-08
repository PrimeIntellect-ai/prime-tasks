#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project_data/folder_a
    mkdir -p /home/user/project_data/folder_b/subfolder
    mkdir -p /home/user/project_data/folder_c

    /bin/bash -c 'for i in {1..40}; do echo "A,Row,$i" >> /home/user/project_data/folder_a/data1.csv; done'
    /bin/bash -c 'for i in {1..45}; do echo "B,Row,$i" >> /home/user/project_data/folder_b/subfolder/data2.csv; done'
    /bin/bash -c 'for i in {1..30}; do echo "C,Row,$i" >> /home/user/project_data/folder_c/data3.csv; done'

    echo "ignore me" > /home/user/project_data/folder_a/notes.txt
    echo "not a csv" > /home/user/project_data/folder_c/data.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
