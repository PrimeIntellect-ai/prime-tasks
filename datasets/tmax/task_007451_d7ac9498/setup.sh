#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
os.makedirs('/home/user/project_assets', exist_ok=True)
with open('/home/user/project_assets/core_engine.bin', 'wb') as f:
    f.write(b'\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\ndata engine\n')
with open('/home/user/project_assets/utils.so', 'wb') as f:
    f.write(b'\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\ndata utils\n')
with open('/home/user/project_assets/fake.bin', 'wb') as f:
    f.write(b'\x7fELX\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\ndata fake\n')
with open('/home/user/project_assets/readme.txt', 'wb') as f:
    f.write(b'just some text\n')
"

    ln -s /home/user/project_assets/core_engine.bin /home/user/project_assets/sym_engine
    ln -s /home/user/project_assets/fake.bin /home/user/project_assets/sym_fake
    ln -s /home/user/project_assets/loop2 /home/user/project_assets/loop1
    ln -s /home/user/project_assets/loop1 /home/user/project_assets/loop2
    ln -s /home/user/project_assets/self_loop /home/user/project_assets/self_loop
    ln -s /home/user/project_assets/does_not_exist /home/user/project_assets/broken_link

    chmod -R 777 /home/user
