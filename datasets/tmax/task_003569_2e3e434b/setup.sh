#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget unzip build-essential
    pip3 install pytest

    mkdir -p /app
    cd /app
    wget https://github.com/richgel999/miniz/releases/download/3.0.2/miniz-3.0.2.zip
    unzip miniz-3.0.2.zip -d miniz-3.0.2
    rm miniz-3.0.2.zip

    cat << 'EOF' > /app/miniz-3.0.2/Makefile
CC = clang-99
CFLAGS = -O0 -g

all: libminiz.a

miniz.o: miniz.c miniz.h
	$(CC) $(CFLAGS) -c miniz.c -o miniz.o

libminiz.a: miniz.o
	ar rcs libminiz.a miniz.o

clean:
	rm -f miniz.o libminiz.a
EOF

    mkdir -p /home/user/config
    mkdir -p /home/user/backups

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/miniz-3.0.2
