#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make protobuf-compiler
    pip3 install pytest protobuf

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/checksum.c
#include <stdint.h>

uint32_t compute_checksum(const char* data, int len) {
    uint32_t sum = 0;
    for(int i = 0; i < len; i++) {
        sum ^= (data[i] << (i % 8));
    }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
libchecksum.so: checksum.o
	gcc -o libchecksum.so checksum.o

checksum.o: checksum.c
	gcc -c checksum.c

clean:
	rm -f *.o *.so
EOF

    cat << 'EOF' > /home/user/project/message.proto
syntax = "proto3";

message Record {
  int32 id = 1;
  string name = 2;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
