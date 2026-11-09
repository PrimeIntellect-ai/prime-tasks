#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/math_perf
    cd /home/user/math_perf

    cat << 'EOF' > math_lib.py
def compute_sum_of_divisors(n):
    if n <= 0: return 0
    total = 0
    for i in range(1, int(n**0.5) + 1):
        if n % i == 0:
            total += i
            if i != n // i:
                total += n // i
    return total
EOF

    cat << 'EOF' > rest_server.py
from flask import Flask, jsonify
from math_lib import compute_sum_of_divisors
import logging

app = Flask(__name__)
log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

@app.route('/sum_divisors/<int:n>', methods=['GET'])
def sum_divisors(n):
    return jsonify({"result": compute_sum_of_divisors(n)})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > math_service.proto
syntax = "proto3";

// TODO: Define the service MathService
// TODO: Define DivisorRequest with an int64 field named 'number'
// TODO: Define DivisorResponse with an int64 field named 'result'
EOF

    cat << 'EOF' > grpc_server.py
import grpc
from concurrent import futures
import math_lib
# TODO: Import generated protobuf modules here

# TODO: Implement the MathServiceServicer class

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    # TODO: Add your Servicer to the server
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

    python3 -c "
import random
random.seed(42)
with open('numbers.txt', 'w') as f:
    for _ in range(100):
        f.write(str(random.randint(10000, 50000)) + '\n')
"

    chmod -R 777 /home/user
