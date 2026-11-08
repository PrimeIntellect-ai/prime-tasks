#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest aiohttp

    mkdir -p /app

    cat << 'EOF' > /app/backend.py
import argparse
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

class SlowHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(0.05) # Simulated slow API
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    server = HTTPServer(('127.0.0.1', args.port), SlowHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /app/verify.py
import asyncio
import aiohttp
import time
import sys
import os

async def fetch(session, url):
    async with session.get(url) as response:
        return await response.read()

async def main():
    url = "http://127.0.0.1:8080/"
    start_time = time.time()

    # Check permissions first
    if not os.path.isdir("/home/user/proxy_logs"):
        print("999.0")
        sys.exit(1)

    stat = os.stat("/home/user/proxy_logs")
    if oct(stat.st_mode)[-3:] != '700':
        print("999.0")
        sys.exit(1)

    try:
        async with aiohttp.ClientSession() as session:
            tasks = [fetch(session, url) for _ in range(200)]
            await asyncio.gather(*tasks)
    except Exception as e:
        print("999.0")
        sys.exit(1)

    duration = time.time() - start_time
    # Print exactly the metric value (duration in seconds) to stdout
    print(f"{duration:.2f}")

if __name__ == "__main__":
    asyncio.run(main())
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
