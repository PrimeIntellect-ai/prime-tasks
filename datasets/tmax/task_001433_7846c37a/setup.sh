#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv
pip3 install pytest

mkdir -p /home/user/app
cd /home/user/app

cat << 'EOF' > requirements.txt
aiohttp==3.8.4
pandas==1.5.3
numpy==1.26.0
EOF

cat << 'EOF' > service.py
import asyncio
import json
import signal
import sys
import os
from aiohttp import web

active_tasks = set()
ema_state = 0.0
alpha = 0.5

async def process_record(payload):
    global ema_state
    # Bug 2: No try-except for JSONDecodeError here or in the caller
    data = json.loads(payload) 
    val = data.get('value', 0)

    # Bug 1: Incorrect formula (using 1 + alpha instead of 1 - alpha)
    ema_state = (val * alpha) + (ema_state * (1 + alpha)) 

    # Simulate processing delay so cancellations can happen
    await asyncio.sleep(0.1)
    return {"status": "ok", "ema": ema_state}

async def handle_request(request):
    payload = await request.text()

    # Bug 3: Task leak on cancellation
    task = asyncio.create_task(process_record(payload))
    active_tasks.add(task)

    try:
        res = await task
        active_tasks.remove(task)
        return web.json_response(res)
    except asyncio.CancelledError:
        # Fails to cancel the inner task and remove it from active_tasks
        raise

def dump_diagnostics(signum, frame):
    with open('/home/user/app/diagnostics.json', 'w') as f:
        json.dump({
            "active_tasks": len(active_tasks),
            "ema": ema_state
        }, f)
    sys.exit(0)

app = web.Application()
app.router.add_post('/ingest', handle_request)

if __name__ == '__main__':
    signal.signal(signal.SIGUSR1, dump_diagnostics)
    web.run_app(app, port=8080)
EOF

cat << 'EOF' > client.py
import asyncio
import aiohttp
import time

async def main():
    async with aiohttp.ClientSession() as session:
        # 1. Send 5 valid requests
        values = [10, 20, 50, 80, 100]
        for v in values:
            async with session.post('http://127.0.0.1:8080/ingest', json={"value": v}) as resp:
                await resp.read()

        # 2. Send malformed request
        try:
            async with session.post('http://127.0.0.1:8080/ingest', data="{bad_json: True}") as resp:
                assert resp.status == 400, "Service did not return 400 for bad JSON"
        except aiohttp.ClientConnectionError:
            print("Connection dropped! Service crashed on bad JSON.")
            return

        # 3. Send 3 requests that are cancelled immediately (triggers CancelledError in handler)
        for i in range(3):
            try:
                task = asyncio.create_task(session.post('http://127.0.0.1:8080/ingest', json={"value": 999}))
                await asyncio.sleep(0.01) # let it connect
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
            except Exception as e:
                pass

        # wait a bit for cancelled tasks to settle
        await asyncio.sleep(0.5)
        print("Client finished workload.")

if __name__ == '__main__':
    asyncio.run(main())
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
