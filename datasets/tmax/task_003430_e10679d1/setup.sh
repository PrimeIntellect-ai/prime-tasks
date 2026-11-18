#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/server.py
import asyncio
import math

class UptimeMonitor:
    def __init__(self):
        # Starts with a large uptime baseline
        self.total_uptime = 100000000.0 

    def add_uptime_delta(self, delta: float):
        # BUG: Precision loss when delta is very small compared to total_uptime
        self.total_uptime += delta

class MetricsServer:
    def __init__(self):
        self.monitor = UptimeMonitor()

    async def _background_worker(self):
        try:
            # Simulating long background processing
            await asyncio.sleep(10)
        except asyncio.CancelledError:
            pass

    async def handle_process_request(self):
        # BUG: If this coroutine is cancelled during the sleep, the worker task leaks
        worker_task = asyncio.create_task(self._background_worker())

        # Simulate waiting for client data before finishing
        await asyncio.sleep(1)

        await worker_task
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
