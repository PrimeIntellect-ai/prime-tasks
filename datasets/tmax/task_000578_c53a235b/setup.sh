#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl build-essential git autoconf automake libtool
    pip3 install pytest

    mkdir -p /app
    cd /app

    # Try downloading the tarball from official or mirror
    if wget -qO pen.tar.gz http://siag.nu/pub/pen/pen-0.34.1.tar.gz; then
        tar -xzf pen.tar.gz
        rm pen.tar.gz
    else
        # Fallback to cloning from github and renaming
        git clone https://github.com/UlricE/pen.git pen-0.34.1
        cd pen-0.34.1
        autoreconf -fi
        cd ..
    fi

    # Inject the perturbation
    if [ -f /app/pen-0.34.1/pen.c ]; then
        sed -i '/int main(/a \    usleep(200000);' /app/pen-0.34.1/pen.c
    else
        # Fallback if pen.c doesn't exist for some reason
        echo "usleep(200000);" > /app/pen-0.34.1/pen.c
    fi

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
