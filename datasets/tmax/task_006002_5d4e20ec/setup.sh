#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest grpcio grpcio-tools websockets

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy
    mkdir -p /home/user/tests

    cat << 'EOF' > /home/user/legacy/scorer.js
class ReadinessScorer {
    constructor(windowSize) {
        this.windowSize = windowSize;
        this.buffer = new Array(windowSize).fill(0);
        this.head = 0;
        this.count = 0;
        this.total = 0;
    }
    add_metric(value) {
        this.total -= this.buffer[this.head];
        this.buffer[this.head] = value;
        this.total += value;
        this.head = (this.head + 1) % this.windowSize;
        if (this.count < this.windowSize) this.count++;
    }
    get_score() {
        if (this.count === 0) return 100;
        return Math.floor(this.total / this.count);
    }
}
module.exports = ReadinessScorer;
EOF

    cat << 'EOF' > /home/user/tests/ws_listener.py
import asyncio
import websockets

async def listen():
    try:
        async with websockets.connect("ws://localhost:8765") as websocket:
            with open("/home/user/alerts.log", "a") as f:
                while True:
                    msg = await websocket.recv()
                    f.write(msg + "\n")
                    f.flush()
    except Exception as e:
        pass

asyncio.run(listen())
EOF

    cat << 'EOF' > /home/user/tests/grpc_client.py
import grpc
import deployment_pb2
import deployment_pb2_grpc
import time

def run():
    channel = grpc.insecure_channel('localhost:50051')
    stub = deployment_pb2_grpc.ReleaseManagerStub(channel)

    metrics = [
        ("auth-svc", 80),
        ("auth-svc", 60),
        ("auth-svc", 50), # Avg: 63
        ("auth-svc", 30), # Avg: 46 (Alert triggered)
        ("payment-svc", 90), # Avg: 56
        ("payment-svc", 10), # Avg: 43 (Alert triggered)
    ]

    for svc, val in metrics:
        stub.SendMetric(deployment_pb2.Metric(service_name=svc, health_value=val))
        time.sleep(0.5)

if __name__ == '__main__':
    run()
EOF

    chmod -R 777 /home/user
