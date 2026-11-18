#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential coreutils sed gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/data
    mkdir -p /home/user/project/docs
    mkdir -p /home/user/project/src

    echo "data 1" > /home/user/project/data/f1.dat
    echo "data 2" > /home/user/project/data/f2.dat
    echo "temp data" > /home/user/project/data/cache.tmp

    echo "int main() {}" > /home/user/project/src/main.c
    echo "compiled" > /home/user/project/src/main.o

    echo "readme" > /home/user/project/docs/readme.txt

    ln -s /home/user/project/data /home/user/project/data/loop_dir
    ln -s /home/user/project/src /home/user/project/docs/src_link

    cat << 'EOF' > /home/user/config.raw
   # This is a messy config
INCLUDE     /home/user/project/data
  INCLUDE /home/user/project/src

EXCLUDE .tmp
   EXCLUDE    .o  
# end of config
EOF

    chmod -R 777 /home/user
