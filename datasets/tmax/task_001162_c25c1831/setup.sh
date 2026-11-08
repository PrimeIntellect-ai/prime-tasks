#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl wget
    pip3 install pytest grpcio grpcio-tools protobuf

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/certs

    # Install grpcurl for potential testing/benchmarking use by the agent
    wget https://github.com/fullstorydev/grpcurl/releases/download/v1.8.7/grpcurl_1.8.7_linux_x86_64.tar.gz
    tar -xzf grpcurl_1.8.7_linux_x86_64.tar.gz -C /usr/local/bin grpcurl
    rm grpcurl_1.8.7_linux_x86_64.tar.gz

    chmod -R 777 /home/user
