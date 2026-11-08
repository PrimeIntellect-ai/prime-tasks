#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    echo '{"running": false, "last_deployed_commit": null}' > /home/user/container_status.json
    touch /home/user/custom.fstab

    chmod -R 777 /home/user
