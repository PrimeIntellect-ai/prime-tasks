#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget build-essential protobuf-compiler
    pip3 install pytest

    # Install Go 1.23
    wget https://go.dev/dl/go1.23.0.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.23.0.linux-amd64.tar.gz
    rm go1.23.0.linux-amd64.tar.gz
    export PATH=/usr/local/go/bin:$PATH

    # Install protoc plugins
    export GOPATH=/opt/go
    export PATH=$PATH:$GOPATH/bin
    go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

    # Link plugins to a system path so they are always available
    ln -s /opt/go/bin/protoc-gen-go /usr/local/bin/
    ln -s /opt/go/bin/protoc-gen-go-grpc /usr/local/bin/
    ln -s /usr/local/go/bin/go /usr/local/bin/go

    # Create vendored C library
    mkdir -p /app/vendored/libtextverify

    cat << 'EOF' > /app/vendored/libtextverify/verify.h
#ifndef VERIFY_H
#define VERIFY_H
int is_valid_text(const char* input);
#endif
EOF

    cat << 'EOF' > /app/vendored/libtextverify/verify.c
#include <string.h>
#include "verify.h"

int is_valid_text(const char* input) {
    char buffer[128];
    strcpy(buffer, input); // BUFFER OVERFLOW
    // dummy check
    if (buffer[0] == '\xff') return 0;
    return 1;
}
EOF

    cat << 'EOF' > /app/vendored/libtextverify/Makefile
all: libtextverify.so

libtextverify.so: verify.o
	gcc -o libtextverify.so verify.o

verify.o: verify.c
	gcc -c verify.c

clean:
	rm -f *.o *.so
EOF

    # Create corpus directories and files
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    echo -n "Hello world" > /home/user/corpus/clean/clean1.txt
    echo -n "Valid text" > /home/user/corpus/clean/clean2.txt

    python3 -c "print('A'*300, end='')" > /home/user/corpus/evil/evil1.txt
    printf "\xffbad" > /home/user/corpus/evil/evil2.txt

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/grpc
    mkdir -p /home/user/server
    mkdir -p /home/user/scan_corpus

    chmod -R 777 /home/user
    chmod -R 777 /app
