#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_source/dirA
    mkdir -p /home/user/data_source/dirB
    mkdir -p /home/user/backup_dest

    echo "Hello World" > /home/user/data_source/file1.txt
    echo "Unchanged text" > /home/user/data_source/dirA/file2.txt
    head -c 1048576 </dev/urandom > /home/user/data_source/dirB/large1.dat
    head -c 1048576 </dev/urandom > /home/user/data_source/dirB/large2.dat

    ln -s /home/user/data_source/dirB /home/user/data_source/dirA/link_to_B
    ln -s /home/user/data_source/dirA /home/user/data_source/dirB/link_to_A

    HASH_FILE2=$(sha256sum /home/user/data_source/dirA/file2.txt | awk '{print $1}')

    cat <<EOF > /home/user/old_manifest.json
{
  "dirA/file2.txt": "${HASH_FILE2}",
  "dirB/large1.dat": "dummy_old_hash_to_force_update"
}
EOF

    chmod -R 777 /home/user
