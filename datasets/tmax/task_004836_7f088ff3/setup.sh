#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential xxd tcpdump
    pip3 install pytest

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean
    mkdir -p /home/user/pcaps

    # Create processor_bin source and compile
    cat << 'EOF' > /tmp/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
int main(int argc, char** argv) {
    if(argc<2) return 0;
    FILE* f = fopen(argv[1], "rb");
    if(!f) return 0;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if(sz < 6) { fclose(f); return 0; }
    uint8_t buf[65536];
    fread(buf, 1, sz, f);
    fclose(f);
    if(buf[0]!=0xDA || buf[1]!=0x7A || buf[2]!=0xBE || buf[3]!=0xEF) return 0;
    uint16_t L = buf[4] | (buf[5]<<8);
    if (L > sz - 6) {
        // Trigger segfault
        int *p = NULL;
        *p = 1;
    }
    return 0;
}
EOF
    gcc -O2 -s /tmp/processor.c -o /app/processor_bin
    rm /tmp/processor.c

    # Generate corpus and pcap/log dummy data
    python3 -c '
import os

def write_payload(path, magic, L, data):
    with open(path, "wb") as f:
        f.write(magic)
        f.write(L.to_bytes(2, "little"))
        f.write(data)

magic = b"\xda\x7a\xbe\xef"

# Clean corpus
write_payload("/app/corpus/clean/clean1.bin", magic, 0, b"")
write_payload("/app/corpus/clean/clean2.bin", magic, 4, b"1234")
write_payload("/app/corpus/clean/clean3.bin", magic, 2, b"1234") # L=2, actual=4, valid

# Evil corpus
write_payload("/app/corpus/evil/evil1.bin", magic, 1, b"")
write_payload("/app/corpus/evil/evil2.bin", magic, 5, b"1234")
write_payload("/app/corpus/evil/evil3.bin", magic, 0xffff, b"1234567890")

# Dummy pcaps and logs
with open("/home/user/crash.log", "w") as f:
    f.write("Crash detected at offset 0x00000000\n")
    f.write("Segmentation fault (core dumped)\n")

with open("/home/user/pcaps/capture.pcap", "wb") as f:
    f.write(b"dummy pcap data")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
