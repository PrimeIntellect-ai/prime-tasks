#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the files using python
    python3 -c "
import os
import struct

base_dir = '/home/user/legacy_docs'
os.makedirs(os.path.join(base_dir, 'section1'), exist_ok=True)
os.makedirs(os.path.join(base_dir, 'section2/deep'), exist_ok=True)
os.makedirs(os.path.join(base_dir, 'section3/misc'), exist_ok=True)

def make_bdoc(path, asset_id, ts):
    with open(path, 'wb') as f:
        f.write(b'BDOC')
        f.write(struct.pack('<I', asset_id))
        f.write(struct.pack('<Q', ts))
        f.write(b'dummy_data_payload_following_header')

make_bdoc(f'{base_dir}/section1/diagram.bdoc', 1042, 1600000000)
make_bdoc(f'{base_dir}/section2/deep/flow.bdoc', 9999, 1600000050)
make_bdoc(f'{base_dir}/section3/misc/architecture.bdoc', 4242, 1600000100)

with open(f'{base_dir}/section1/intro.md', 'w') as f:
    f.write('Welcome to section 1.\nSee diagram: [[ASSET_REF: diagram.bdoc]]\nEnd of section.\n')

with open(f'{base_dir}/section2/deep/details.md', 'w') as f:
    f.write('Details here.\nFlowchart: [[ASSET_REF: flow.bdoc]]\nAlso reference: [[ASSET_REF: architecture.bdoc]]\n')
"

    chmod -R 777 /home/user
