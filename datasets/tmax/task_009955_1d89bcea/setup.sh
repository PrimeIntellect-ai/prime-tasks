#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/storage_data/dir1
    mkdir -p /home/user/storage_data/dir2
    mkdir -p /home/user/outside_dir

    python3 -c "
def make_zxt(path, chunks):
    with open(path, 'wb') as f:
        for count, char in chunks:
            f.write(bytes([count]))
            f.write(char.encode('utf-16le'))

make_zxt('/home/user/storage_data/file1.zxt', [(3, 'A'), (2, 'B')])
make_zxt('/home/user/storage_data/dir1/file2.zxt', [(1, 'C'), (4, 'X')])
make_zxt('/home/user/outside_dir/file3.zxt', [(2, 'D'), (1, 'E')])
"

    ln -s /home/user/storage_data/dir1 /home/user/storage_data/dir2/link_to_dir1
    ln -s /home/user/storage_data/dir1 /home/user/storage_data/dir1/loop_link
    ln -s /home/user/outside_dir /home/user/storage_data/link_to_outside
    ln -s /home/user/storage_data/file1.zxt /home/user/storage_data/dir1/link_to_file1.zxt

    chown -R user:user /home/user
    chmod -R 777 /home/user
