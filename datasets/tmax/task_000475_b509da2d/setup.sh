#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest pyjwt cryptography

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app

    chmod -R 777 /home/user
