#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest aiohttp

# Create the vendored package directory
mkdir -p /app/vendored/netprobe-1.0.0/netprobe

# Create setup.py
cat << 'EOF' > /app/vendored/netprobe-1.0.0/setup.py
from setuptools import setup, find_packages

setup(
    name="netprobe",
    version="1.0.0",
    packages=find_packages(),
    install_requires=["aiohttp"],
)
EOF

# Create netprobe/__init__.py
touch /app/vendored/netprobe-1.0.0/netprobe/__init__.py

# Create netprobe/client.py with the deliberate perturbation
cat << 'EOF' > /app/vendored/netprobe-1.0.0/netprobe/client.py
import aiohttp
import asyncio
import time

async def fetch(session, url):
    time.sleep(0.1)  # Deliberate perturbation
    try:
        async with session.get(url) as response:
            await response.read()
            return True
    except Exception:
        return False

async def run_load_test(url, duration):
    async with aiohttp.ClientSession() as session:
        start_time = time.time()
        tasks = []
        completed_requests = 0

        while time.time() - start_time < duration:
            # Create a batch of tasks
            batch = [fetch(session, url) for _ in range(50)]
            results = await asyncio.gather(*batch, return_exceptions=True)
            completed_requests += sum(1 for r in results if r is True)

        end_time = time.time()
        actual_duration = end_time - start_time
        return completed_requests / actual_duration if actual_duration > 0 else 0
EOF

# Create netprobe/__main__.py
cat << 'EOF' > /app/vendored/netprobe-1.0.0/netprobe/__main__.py
import argparse
import asyncio
import json
from .client import run_load_test

def main():
    parser = argparse.ArgumentParser(description="Netprobe Load Tester")
    parser.add_argument("--url", required=True, help="Target URL")
    parser.add_argument("--duration", type=int, required=True, help="Duration in seconds")
    parser.add_argument("--output", required=True, help="Output JSON file path")
    args = parser.parse_args()

    rps = asyncio.run(run_load_test(args.url, args.duration))

    with open(args.output, "w") as f:
        json.dump({"requests_per_second": rps}, f)

    print(f"Load test completed. RPS: {rps:.2f}")

if __name__ == "__main__":
    main()
EOF

# Create the user
useradd -m -s /bin/bash user || true

# Ensure proper permissions
chmod -R 777 /home/user
chmod -R 777 /app
