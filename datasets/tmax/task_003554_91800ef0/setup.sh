#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    # Generate traffic.pcap
    python3 -c "
from scapy.all import *
pkts = [IP(dst='127.0.0.1')/TCP(dport=8888)/Raw(load='GET /api/v1/trigger_leak_992 HTTP/1.1\r\nHost: localhost\r\n\r\n')]
wrpcap('/home/user/traffic.pcap', pkts)
"

    # Generate crash_dump.bin (ensuring it's > 1MB)
    head -c 1M </dev/urandom > /home/user/crash_dump.bin
    echo -n "FLAG_{m3m0ry_t4sk_l34k_f0und}" >> /home/user/crash_dump.bin
    head -c 1M </dev/urandom >> /home/user/crash_dump.bin

    # Create server.py
    cat << 'EOF' > /home/user/server.py
import asyncio

async def background_worker():
    try:
        await asyncio.sleep(3600)
    except asyncio.CancelledError:
        pass

async def handle_client(reader, writer):
    # This task is leaked because it is never awaited or cancelled
    task = asyncio.create_task(background_worker())

    data = await reader.read(100)
    writer.write(b"HTTP/1.1 200 OK\r\n\r\n")
    await writer.drain()
    writer.close()
    await writer.wait_closed()
    # BUG: task is leaked here

async def start_server():
    server = await asyncio.start_server(handle_client, '127.0.0.1', 8888)
    return server
EOF

    # Create test_build.py
    cat << 'EOF' > /home/user/test_build.py
import asyncio
from server import start_server

async def run_test():
    srv = await start_server()

    # Simulate a client connecting and disconnecting
    reader, writer = await asyncio.open_connection('127.0.0.1', 8888)
    writer.write(b"GET / HTTP/1.1\r\n\r\n")
    await writer.drain()
    await reader.read(100)
    writer.close()
    await writer.wait_closed()

    # Allow event loop to process closures
    await asyncio.sleep(0.1)

    # Check for leaked tasks
    leaked = [t for t in asyncio.all_tasks() if t.get_coro().__name__ == 'background_worker']

    if leaked:
        print("FAIL: Leaked background tasks detected!")
        import sys
        sys.exit(1)

    print("PASS")
    srv.close()
    await srv.wait_closed()

if __name__ == '__main__':
    asyncio.run(run_test())
EOF

    chmod +x /home/user/test_build.py
    chmod -R 777 /home/user
