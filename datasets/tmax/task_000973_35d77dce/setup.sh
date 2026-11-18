#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data
    echo -n "project info" > "/home/user/raw_data/Project Alpha.doc"
    echo -n "money" > "/home/user/raw_data/FINANCIAL_report_2023.XLS"
    echo -n "fake image" > "/home/user/raw_data/Image_001.JPG"
    echo -n "just notes" > "/home/user/raw_data/notes.txt"

    chmod -R 777 /home/user
