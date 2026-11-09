#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential wget curl
    pip3 install pytest

    mkdir -p /app/vendored/cJSON
    mkdir -p /app/local/lib
    mkdir -p /app/local/include

    wget https://raw.githubusercontent.com/DaveGamble/cJSON/v1.7.15/cJSON.c -O /app/vendored/cJSON/cJSON.c
    wget https://raw.githubusercontent.com/DaveGamble/cJSON/v1.7.15/cJSON.h -O /app/vendored/cJSON/cJSON.h

    cat << 'EOF' > /app/vendored/cJSON/Makefile
CC = gcc
CFLAGS = -O2 -Wall

all: libcJSON.so

libcJSON.so: cJSON.c
	$(CC) $(CFLAGS) -o libcJSON.so cJSON.c

install: libcJSON.so
	mkdir -p /app/local/lib /app/local/include
	cp libcJSON.so /app/local/lib/
	cp cJSON.h /app/local/include/
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
