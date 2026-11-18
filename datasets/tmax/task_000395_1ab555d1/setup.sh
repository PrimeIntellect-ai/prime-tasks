#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest fastapi uvicorn scapy

    # Create app directory
    mkdir -p /app/vendored-async-svc-1.2.0

    # Create requirements.txt
    cat << 'EOF' > /app/vendored-async-svc-1.2.0/requirements.txt
fastapi
uvicorn
EOF

    # Create start.sh with the typo
    cat << 'EOF' > /app/vendored-async-svc-1.2.0/start.sh
#!/bin/bash
PY_BIN="python3.8"
$PY_BIN -m uvicorn server:app --host 127.0.0.1 --port 8080
EOF
    chmod +x /app/vendored-async-svc-1.2.0/start.sh

    # Create server.py with the concurrency bug
    cat << 'EOF' > /app/vendored-async-svc-1.2.0/server.py
import asyncio
from fastapi import FastAPI, Request

app = FastAPI()

# Track active tasks for stats
active_tasks = set()

async def worker_logic():
    try:
        # Simulate long asynchronous processing
        await asyncio.sleep(10)
    finally:
        pass

@app.post("/process")
async def process(request: Request):
    # Bug: task is created and awaited, but if the client disconnects
    # and the request handler is cancelled, the background task is NOT cancelled.
    task = asyncio.create_task(worker_logic())
    active_tasks.add(task)
    task.add_done_callback(active_tasks.discard)

    # Awaiting the task directly. If the request is cancelled, 
    # this await raises CancelledError, but 'task' keeps running.
    await task
    return {"status": "ok"}

@app.get("/__stats__")
async def stats():
    # Return count of active background tasks
    return {"active_tasks": len(active_tasks)}
EOF

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate incident.pcap
    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import IP, TCP, Raw, wrpcap

packets = [
    IP(dst="127.0.0.1", src="127.0.0.1")/TCP(sport=54321, dport=8080, flags="S", seq=1000),
    IP(dst="127.0.0.1", src="127.0.0.1")/TCP(sport=54321, dport=8080, flags="A", seq=1001, ack=2000),
    IP(dst="127.0.0.1", src="127.0.0.1")/TCP(sport=54321, dport=8080, flags="PA", seq=1001, ack=2000)/Raw(load="POST /process HTTP/1.1\r\nHost: 127.0.0.1:8080\r\n\r\n"),
    IP(dst="127.0.0.1", src="127.0.0.1")/TCP(sport=54321, dport=8080, flags="R", seq=1050)
]

wrpcap("/home/user/incident.pcap", packets)
EOF
    python3 /tmp/gen_pcap.py

    # Set permissions
    chown -R user:user /app/vendored-async-svc-1.2.0
    chown -R user:user /home/user
    chmod -R 777 /home/user
