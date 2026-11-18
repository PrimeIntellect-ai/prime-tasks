#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ticket_4092
    cd /home/user/ticket_4092

    cat << 'EOF' > worker.py
import struct
import math
import sys

def sum_of_proper_divisors(n):
    if n <= 1:
        return 0
    s = 1
    # BUG 1: The math logic misses the square root itself if n is a perfect square
    # and it includes the number 'n' if we aren't careful, but here we just do proper divisors.
    # Actually, the bug here is that it adds the square root twice for perfect squares:
    for i in range(2, int(math.isqrt(n)) + 1):
        if n % i == 0:
            s += i
            s += n // i
    return s

def process_payload(payload):
    # BUG 2: Unpacks as little-endian signed 64-bit integer ('<q')
    # The network traffic actually sends big-endian unsigned 64-bit integers ('>Q')
    try:
        val = struct.unpack('<q', payload)[0]
        res = sum_of_proper_divisors(val)
        print(f"Processed {val}: {res}")
        return val, res
    except Exception as e:
        print(f"Error processing {payload}: {e}")
        raise

if __name__ == "__main__":
    # For testing manually
    pass
EOF

    cat << 'EOF' > worker.log
Processed 496: 496
Error processing b'\x00\x00\x00\x00\x00\x00\x1f\xc0': ValueError: math domain error
Traceback (most recent call last):
  File "worker.py", line 23, in process_payload
    res = sum_of_proper_divisors(val)
  File "worker.py", line 12, in sum_of_proper_divisors
    for i in range(2, int(math.isqrt(n)) + 1):
ValueError: math domain error
EOF

    python3 -c "
from scapy.all import wrpcap, Ether, IP, UDP
import struct

# Numbers to send: 
# 28 (Perfect) -> sum = 28
# 36 (Perfect square) -> divisors: 1, 2, 3, 4, 6, 9, 12, 18 -> sum = 55
# 8128 (Perfect) -> sum = 8128
# 100 (Perfect square) -> divisors: 1, 2, 4, 5, 10, 20, 25, 50 -> sum = 117
numbers = [28, 36, 8128, 100]

packets = []
for n in numbers:
    # Encoded as Big-Endian Unsigned 64-bit integer
    payload = struct.pack('>Q', n)
    pkt = Ether()/IP(dst='127.0.0.1')/UDP(dport=9000)/payload
    packets.append(pkt)

wrpcap('traffic.pcap', packets)
"

    chmod -R 777 /home/user
