#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev nginx
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    printf "CI-RUNNER-9942-AUTH" > /home/user/runner_id.bin

    chmod -R 777 /home/user
