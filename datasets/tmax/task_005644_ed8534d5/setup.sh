#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    echo "110B060F181E176A070B061D0B180F6A0E0F1E0F091E0F0E6A0C1805076A7B7378647B7C72647B797D647E786A0F040E" > /home/user/dump.hex

    chmod -R 777 /home/user
