#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar file findutils grep coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/repo

    cd /home/user
    mkdir -p base_dir/bin inc2_dir/bin inc3_dir/bin

    cp /bin/ls base_dir/bin/app1
    cp /bin/pwd base_dir/bin/app2
    tar -cf incoming/1_base.tar -C base_dir bin/

    cp /bin/echo inc2_dir/bin/app3
    touch inc2_dir/bad_file.txt
    python3 -c "
import tarfile
with tarfile.open('incoming/2_inc.tar', 'w') as t:
    t.add('inc2_dir/bin/app3', arcname='bin/app3')
    t.add('inc2_dir/bad_file.txt', arcname='../evil.sh')
"

    cp /bin/cat inc3_dir/bin/app4
    tar -cf incoming/3_inc.tar -C inc3_dir bin/

    python3 -c "
import tarfile
with tarfile.open('incoming/4_inc.tar', 'w') as t:
    t.add('inc3_dir/bin/app4', arcname='/etc/shadow_overwrite')
"

    rm -rf base_dir inc2_dir inc3_dir

    chmod -R 777 /home/user
