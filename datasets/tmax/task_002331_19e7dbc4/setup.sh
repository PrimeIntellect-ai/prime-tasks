#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake build-essential zlib1g-dev git
    pip3 install pytest

    mkdir -p /home/user/data_lake/financials
    mkdir -p /home/user/data_lake/engineering

    echo -n "CONFIDENTIAL_DATA_A" > /home/user/data_lake/financials/2004.dat
    echo -n "PROJECT_BLUEPRINT_V1" > /home/user/data_lake/engineering/blueprint.dat
    echo -n "MISC_DATA_99" > /home/user/data_lake/misc.dat

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
