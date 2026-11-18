#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    echo "http://api.local/v1/math_encode?data=SuperSecretMathAgent&key=17" > /home/user/request.txt

    chmod -R 777 /home/user
