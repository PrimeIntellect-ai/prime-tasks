#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # Create the input data in UTF-16LE format
    python3 -c "open('/home/user/input_data.bin', 'wb').write('12,45,78,111,144,177,210'.encode('utf-16le'))"

    chmod -R 777 /home/user
