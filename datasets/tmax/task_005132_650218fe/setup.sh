#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/archive

    python3 -c "
with open('/home/user/raw_data/alpha_sensor.dat', 'wb') as f:
    f.write(b'ALPHA_DATA_START ' + b'01010101'*1000 + b' END')

with open('/home/user/raw_data/beta_sensor.dat', 'wb') as f:
    f.write(b'BETA_DATA_START ' + b'10101010'*1500 + b' END')

with open('/home/user/raw_data/gamma_sensor.dat', 'wb') as f:
    f.write(b'GAMMA_DATA_START ' + b'11223344'*2000 + b' END')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
