#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/artifacts/raw_data
    echo "MLOps is very cool" > /home/user/artifacts/raw_data/experiment_alpha.txt
    echo "Data science and C++ testing" > /home/user/artifacts/raw_data/experiment_beta.txt
    echo "Tokenization dataset preparation steps for LLMs" > /home/user/artifacts/raw_data/experiment_gamma.txt
    echo "Ignore this csv,1,2,3" > /home/user/artifacts/raw_data/ignore.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
