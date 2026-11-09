#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb tcpdump tshark
    pip3 install pytest

    mkdir -p /home/user/engine
    cat << 'EOF' > /home/user/engine/calc.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <base> <delta>\n", argv[0]);
        return 1;
    }

    float base = atof(argv[1]);
    float delta = atof(argv[2]);

    // The bug: float precision limits cause catastrophic cancellation
    // If base is large (e.g. 100000.0) and delta is small (e.g. 0.001),
    // combined - base evaluates to 0.0f
    float combined = base + delta;
    float actual_delta = combined - base;

    // This causes a divide-by-zero (SIGFPE)
    int metric = (int)(10000.0f / actual_delta);

    printf("%d\n", metric);
    return 0;
}
EOF
    gcc /home/user/engine/calc.c -o /home/user/engine/calc

    python3 -c '
import struct
import time

def write_pcap(filename, packets):
    # Global header
    magic_number = 0xa1b2c3d4
    version_major = 2
    version_minor = 4
    thiszone = 0
    sigfigs = 0
    snaplen = 65535
    network = 1 # Ethernet

    with open(filename, "wb") as f:
        f.write(struct.pack("<IHHiIII", magic_number, version_major, version_minor, thiszone, sigfigs, snaplen, network))

        for payload in packets:
            # Ethernet header (14 bytes)
            eth = b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08\x00"
            # IP header (20 bytes) - src 1.1.1.1, dst 2.2.2.2, proto UDP (17)
            ip = b"\x45\x00\x00" + struct.pack(">H", 28 + len(payload)) + b"\x00\x00\x40\x00\x40\x11\x00\x00\x01\x01\x01\x01\x02\x02\x02\x02"
            # UDP header (8 bytes) - src port 1234, dst port 5000
            udp = struct.pack(">HHHH", 1234, 5000, 8 + len(payload), 0)

            packet = eth + ip + udp + payload

            ts_sec = int(time.time())
            ts_usec = 0
            incl_len = len(packet)
            orig_len = len(packet)

            f.write(struct.pack("<IIII", ts_sec, ts_usec, incl_len, orig_len))
            f.write(packet)

# Create 3 packets. 
# Packet 1: 10.0, 2.0 (OK)
# Packet 2: 100000.0, 0.001 (CRASH)
# Packet 3: 50.0, 5.0 (OK)
p1 = struct.pack("<ff", 10.0, 2.0)
p2 = struct.pack("<ff", 100000.0, 0.001)
p3 = struct.pack("<ff", 50.0, 5.0)

write_pcap("/home/user/traffic.pcap", [p1, p2, p3])
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
