#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
with open("/home/user/raw_data.tsv", "wb") as f:
    f.write(b"1\t10.5\tT\xe9mpSensor\n2\t12.0\tT\xe9mpSensor\n5\t15.0\tT\xe9mpSensor\n6\t14.5\tT\xe9mpSensor\n")
'

    chmod -R 777 /home/user
