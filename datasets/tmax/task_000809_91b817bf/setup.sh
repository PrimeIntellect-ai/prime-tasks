#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gawk sed curl
    pip3 install pytest

    # Create directories
    mkdir -p /tmp/staging
    mkdir -p /home/user/workspace

    # Generate the initial data using Python
    python3 -c '
import os
import tarfile

csv_content = """Date,NewYork_Temperature,Tokyo_温度,Paris_Température,Moscow_Влажность
2023-01-15,5.2,8.1,6.5,80
2023-02-20,6.1,9.2,7.0,75
2023-03-10,10.5,14.0,11.2,60
"""

raw_path = "/tmp/staging/raw_sensors.csv"
with open(raw_path, "w", encoding="utf-16le") as f:
    f.write(csv_content)

tar_path = "/tmp/staging/sensor_archive.tar.gz"
with tarfile.open(tar_path, "w:gz") as tar:
    tar.add(raw_path, arcname="raw_sensors.csv")

os.remove(raw_path)
'

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/workspace
    chmod -R 777 /home/user
    chmod -R 777 /tmp/staging
