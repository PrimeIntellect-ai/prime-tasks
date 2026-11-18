#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/binaries

    python3 -c '
import os
with open("/home/user/binaries/service_a.bin", "wb") as f:
    f.write(b"\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00")
    f.write(b"Some binary data here. SSN: 123-45-6789 end of data.")

with open("/home/user/binaries/service_b.bin", "wb") as f:
    f.write(b"\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00")
    f.write(b"Admin record: 987-65-4321. Backup: 000-00-0000.")

with open("/home/user/binaries/config.bin", "wb") as f:
    f.write(b"\xeb\x4c\x46\x02\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00")
    f.write(b"Fake ELF file with SSN: 555-66-7777 inside.")
'

    echo "X-Frame-Options: DENY" > /home/user/headers.conf
    echo "X-Content-Type-Options: nosniff" >> /home/user/headers.conf

    chmod -R 755 /home/user/binaries
    chmod 644 /home/user/headers.conf
    chmod -R 777 /home/user
