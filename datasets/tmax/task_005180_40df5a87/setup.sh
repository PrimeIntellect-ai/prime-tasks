#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/scheduler-pr
    cat << 'EOF' > /home/user/scheduler-pr/server.py
import asyncio
import websockets
import json

async def schedule(websocket, path):
    async for message in websocket:
        data = json.loads(message)
        tasks = data.get("tasks", [])
        workers = data.get("workers", [])

        assignments = []
        possible = True

        for task in tasks:
            assigned = False
            for worker in workers:
                if worker.get("skill") == task.get("required_skill"):
                    assignments.append({"task_id": task["id"], "worker_id": worker["id"]})
                    assigned = True
                    break # Bug: worker is not removed or marked as used

            if not assigned:
                possible = False
                break

        if possible:
            response = {"assignments": assignments}
        else:
            response = {"error": "unsatisfiable"}

        # Bug: Sends dict instead of string
        await websocket.send(response)

        # Bug: Does not log to /home/user/scheduler_log.jsonl

async def main():
    async with websockets.serve(schedule, "127.0.0.1", 8765):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
EOF

    chmod -R 777 /home/user
