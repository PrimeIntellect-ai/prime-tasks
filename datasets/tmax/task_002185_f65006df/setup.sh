#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    mkdir -p /home/user/data
    mkdir -p /app/async-build-cache-1.0.0/async_build_cache

    # Create build.log
    cat << 'EOF' > /home/user/logs/build.log
2023-10-24 10:00:00 Build started
2023-10-24 10:00:01 Connecting to cache...
2023-10-24 10:00:02 Cache response OK for TXN 1044
2023-10-24 10:00:02 Cache response OK for TXN 1045
2023-10-24 10:00:03 Connection timeout for TXN 1046
2023-10-24 10:00:03 Cache daemon unreachable
EOF

    # Create cache.wal
    cat << 'EOF' > /home/user/data/cache.wal
[2023-10-24T10:00:01] [1044] SET build_hash_A 99283
[2023-10-24T10:00:02] [1045] SET build_hash_B 11223
[2023-10-24T10:00:03] [1046] SET build_hash_C 445
[2023-10-24T10:00:03] [1047] SET bui
EOF

    # Generate traffic.pcap using scapy
    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import *
pkts = [
    IP(src="127.0.0.1", dst="127.0.0.1")/TCP(sport=12345, dport=8888, flags="PA")/Raw(load="TXN_ID: 1045\n"),
    IP(src="127.0.0.1", dst="127.0.0.1")/TCP(sport=8888, dport=12345, flags="PA")/Raw(load="ACK TXN_ID: 1045\n"),
    IP(src="127.0.0.1", dst="127.0.0.1")/TCP(sport=12345, dport=8888, flags="PA")/Raw(load="TXN_ID: 1046\n"),
    IP(src="127.0.0.1", dst="127.0.0.1")/TCP(sport=8888, dport=12345, flags="R")
]
wrpcap("/home/user/logs/traffic.pcap", pkts)
EOF
    python3 /tmp/gen_pcap.py
    rm /tmp/gen_pcap.py

    # Create the vendored package
    cat << 'EOF' > /app/async-build-cache-1.0.0/setup.py
from setuptools import setup, find_packages

setup(
    name="async-build-cache",
    version="1.0.0",
    packages=find_packages(),
)
EOF

    touch /app/async-build-cache-1.0.0/async_build_cache/__init__.py

    cat << 'EOF' > /app/async-build-cache-1.0.0/async_build_cache/server.py
import asyncio

async def handle_client(reader, writer):
    while True:
        try:
            data = await reader.read(100)
            if not data:
                break
            writer.write(b"ACK\n")
            await writer.drain()
        except asyncio.CancelledError:
            pass # BUG: leaks connection because it doesn't break
        except Exception:
            break

async def main():
    server = await asyncio.start_server(handle_client, '127.0.0.1', 8888)
    async with server:
        await server.serve_forever()

if __name__ == '__main__':
    asyncio.run(main())
EOF

    # Create verify_throughput.py
    cat << 'EOF' > /home/user/verify_throughput.py
import re
import sys

def main():
    try:
        with open('/app/async-build-cache-1.0.0/async_build_cache/server.py', 'r') as f:
            code = f.read()

        # Check if the bug is still present
        if re.search(r'except asyncio\.CancelledError:\s+pass', code):
            print(50.0)
        else:
            print(1200.0)
    except Exception as e:
        print(0.0)

if __name__ == '__main__':
    main()
EOF

    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
