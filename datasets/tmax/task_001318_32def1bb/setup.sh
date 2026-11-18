#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind
    pip3 install pytest scapy

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    cat << 'EOF' > /tmp/daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main() {
    uint8_t magic[2];
    if (fread(magic, 1, 2, stdin) != 2) return 0;
    if (magic[0] != 0x54 || magic[1] != 0x44) return 0;

    while (1) {
        uint8_t type;
        if (fread(&type, 1, 1, stdin) != 1) break;
        uint8_t len_bytes[2];
        if (fread(len_bytes, 1, 2, stdin) != 2) break;
        uint16_t length = (len_bytes[0] << 8) | len_bytes[1];

        if (type == 3) {
            void *ptr = malloc(length);
            if (!ptr) break;
            size_t read_bytes = fread(ptr, 1, length, stdin);
            if (read_bytes < length) {
                // Leak memory and abort
                return 1;
            }
            free(ptr);
        } else {
            void *ptr = malloc(length);
            if (ptr) {
                size_t read_bytes = fread(ptr, 1, length, stdin);
                free(ptr);
                if (read_bytes < length) {
                    return 1;
                }
            }
        }
    }
    return 0;
}
EOF

    gcc -static -O2 /tmp/daemon.c -o /app/telemetry_daemon
    strip /app/telemetry_daemon
    rm /tmp/daemon.c

    cat << 'EOF' > /tmp/setup.py
import os
import random
import struct
from scapy.all import IP, TCP, Ether, wrpcap

def make_record(t, length, data=None):
    if data is None:
        data = os.urandom(length)
    return struct.pack(">BH", t, length) + data[:length]

def make_payload(is_evil):
    magic = b"\x54\x44"
    payload = magic
    if is_evil:
        for _ in range(random.randint(0, 2)):
            l = random.randint(1, 10)
            payload += make_record(random.choice([1, 2, 4]), l)
        l = random.randint(10, 50)
        rem = random.randint(0, l - 1)
        payload += struct.pack(">BH", 3, l) + os.urandom(rem)
    else:
        for _ in range(random.randint(1, 4)):
            t = random.choice([1, 2, 3, 4])
            l = random.randint(1, 20)
            payload += make_record(t, l)
        if random.random() < 0.3:
            t = random.choice([1, 2, 4])
            l = random.randint(10, 50)
            rem = random.randint(0, l - 1)
            payload += struct.pack(">BH", t, l) + os.urandom(rem)
    return payload

random.seed(42)
evil_payloads = [make_payload(True) for _ in range(50)]
clean_payloads = [make_payload(False) for _ in range(50)]

for i, p in enumerate(evil_payloads):
    with open(f"/app/corpus/evil/{i}.bin", "wb") as f:
        f.write(p)

for i, p in enumerate(clean_payloads):
    with open(f"/app/corpus/clean/{i}.bin", "wb") as f:
        f.write(p)

packets = []
for p in evil_payloads[:10] + clean_payloads[:10]:
    pkt = Ether()/IP(dst="10.0.0.2")/TCP(dport=8080)/p
    packets.append(pkt)
wrpcap("/app/traffic.pcap", packets)

with open("/app/daemon_state.wal", "wb") as f:
    for p in evil_payloads[10:20] + clean_payloads[10:20]:
        f.write(b"SQLITE_WAL_FRAME" + p + b"END_FRAME")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
