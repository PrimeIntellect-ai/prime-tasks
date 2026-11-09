#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest grpcio grpcio-tools websockets

    # Install system packages required for the task
    apt-get install -y \
        build-essential \
        cmake \
        libgrpc++-dev \
        protobuf-compiler-grpc \
        libprotobuf-dev \
        libwebsocketpp-dev \
        libboost-all-dev \
        nlohmann-json3-dev

    # Create project directory
    mkdir -p /home/user/project

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
