#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libgsl-dev
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Generate the binary data file
    python3 -c '
import struct
with open("/home/user/sensor_data.bin", "wb") as f:
    for i in range(1, 1001):
        x = float(i)
        y = float(i * 2.0)
        f.write(struct.pack("dd", x, y))
'

    # Set permissions
    chmod -R 777 /home/user
