#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
os.makedirs("/home/user/storage_spool", exist_ok=True)
with open("/home/user/storage_spool/data_01.dat", "wb") as f:
    f.write(b"Hello World\n")
with open("/home/user/storage_spool/data_02.dat", "wb") as f:
    f.write(b"Binary\x00Data")
with open("/home/user/storage_spool/data_03.dat", "wb") as f:
    f.write(b"More text logs for the system.")
with open("/home/user/storage_spool/data_04.dat", "wb") as f:
    f.write(b"\x00")
with open("/home/user/storage_spool/data_05.dat", "wb") as f:
    f.write(b"Final text.")
'

    chmod -R 777 /home/user
