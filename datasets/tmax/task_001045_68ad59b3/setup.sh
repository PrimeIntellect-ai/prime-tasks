#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

python3 -c "
import os
import tarfile

os.makedirs('/home/user/incoming', exist_ok=True)
os.makedirs('/home/user/workspace', exist_ok=True)

safe_file1 = b'Project asset data A'
safe_file2 = b'Project asset data B'
safe_file3 = b'Project asset data A'
evil_file1 = b'Malicious payload 1'
evil_file2 = b'Malicious payload 2'

temp_tar_path = '/home/user/temp_vendor.tar.gz'
with tarfile.open(temp_tar_path, 'w:gz') as tar:
    for name, data in [('assets/data1.bin', safe_file1), ('assets/data2.bin', safe_file2), ('docs/readme.txt', safe_file3)]:
        clean_name = name.replace('/', '_')
        path = f'/tmp/{clean_name}'
        with open(path, 'wb') as f:
            f.write(data)
        tar.add(path, arcname=name)
        os.remove(path)

    path1 = '/tmp/evil1'
    with open(path1, 'wb') as f: f.write(evil_file1)
    tar.add(path1, arcname='../escaped.txt')

    path2 = '/tmp/evil2'
    with open(path2, 'wb') as f: f.write(evil_file2)
    tar.add(path2, arcname='/home/user/absolute_evil.txt')

chunk_size = 200
part_num = 1
with open(temp_tar_path, 'rb') as infile:
    while True:
        chunk = infile.read(chunk_size)
        if not chunk:
            break
        with open(f'/home/user/incoming/vendor_data.tar.gz.part{part_num}', 'wb') as outfile:
            outfile.write(chunk)
        part_num += 1

os.remove(temp_tar_path)
"

chmod -R 777 /home/user
