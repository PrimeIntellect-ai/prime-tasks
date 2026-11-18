#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gcc-multilib
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/messy_project/src
    mkdir -p /home/user/messy_project/build/bin
    mkdir -p /home/user/messy_project/build/lib

    echo "void main(){}" > /home/user/messy_project/src/main.c
    echo "log data" > /home/user/messy_project/build/build.log

    echo "int main(){return 0;}" | gcc -x c - -o /home/user/messy_project/build/bin/app_64
    echo "int main(){return 0;}" | gcc -m32 -x c - -o /home/user/messy_project/build/bin/app_32
    echo "int lib(){return 1;}" | gcc -shared -fPIC -x c - -o /home/user/messy_project/build/lib/libtest.so

    chmod -R 777 /home/user
