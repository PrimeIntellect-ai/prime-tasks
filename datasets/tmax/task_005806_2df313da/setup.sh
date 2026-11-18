#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
os.makedirs('/home/user/config_tree', exist_ok=True)
with open('/home/user/config_tree/file1.bin', 'wb') as f:
    f.write(b'MAGIC123_EXTRA_DATA')
with open('/home/user/config_tree/file2.bin', 'wb') as f:
    f.write(b'CONF\x00\x01\x02\x03')
with open('/home/user/config_tree/file3.txt', 'wb') as f:
    f.write(b'SHORT')
"

    ln -s /home/user/config_tree/file1.bin /home/user/config_tree/link_ok
    ln -s /home/user/config_tree/link_loop2 /home/user/config_tree/link_loop1
    ln -s /home/user/config_tree/link_loop1 /home/user/config_tree/link_loop2
    ln -s /home/user/config_tree/nonexistent /home/user/config_tree/link_broken

    cat << 'EOF' > /home/user/backup.conf
/home/user/config_tree/file1.bin
/home/user/config_tree/file2.bin
/home/user/config_tree/file3.txt
/home/user/config_tree/link_ok
/home/user/config_tree/link_loop1
/home/user/config_tree/link_broken
EOF

    chown -R user:user /home/user/config_tree /home/user/backup.conf
    chmod -R 777 /home/user
