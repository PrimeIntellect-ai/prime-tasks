#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
os.makedirs('/home/user/configs/raw', exist_ok=True)
os.makedirs('/home/user/configs/archive', exist_ok=True)

valid_header = b'\xCF\xFA\xED\xFE'
invalid_header = b'\x00\x00\x00\x00'

def create_file(path, header, version):
    with open(path, 'wb') as f:
        f.write(header)
        f.write(f'VERSION: {version}\nkey=value\n'.encode('utf-8'))

create_file('/home/user/configs/raw/app_v10.cfg', valid_header, 10)
create_file('/home/user/configs/raw/app_v15.cfg', valid_header, 15)
create_file('/home/user/configs/raw/app_v05.cfg', valid_header, 5)
create_file('/home/user/configs/raw/app_v20_badperms.cfg', valid_header, 20)
create_file('/home/user/configs/raw/app_v30_badhead.cfg', invalid_header, 30)
"

    chmod -R 777 /home/user

    # Fix specific file permissions after recursive chmod
    chmod 644 /home/user/configs/raw/app_v10.cfg
    chmod 644 /home/user/configs/raw/app_v15.cfg
    chmod 644 /home/user/configs/raw/app_v05.cfg
    chmod 600 /home/user/configs/raw/app_v20_badperms.cfg
    chmod 644 /home/user/configs/raw/app_v30_badhead.cfg
