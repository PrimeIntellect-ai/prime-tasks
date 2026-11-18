#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask fastapi uvicorn requests

    mkdir -p /app/obfuscation_solver
    touch /app/obfuscation_solver/__init__.py

    cat << 'EOF' > /app/obfuscation_solver/math_utils.py
import math

def custom_activation(x):
    # Bug: Naive Taylor series expansion for e^(-x) causes catastrophic cancellation for large x
    result = 0.0
    for n in range(50):
        result += ((-x)**n) / math.factorial(n)
    return result
EOF

    cat << 'EOF' > /app/obfuscation_solver/serializer.py
import struct

def unpack_key(data):
    # Bug: Unpacks as 32-bit unsigned int ('<I') instead of 64-bit unsigned long long ('<Q')
    return struct.unpack('<I', data[0:4])[0]
EOF

    cat << 'EOF' > /app/obfuscation_solver/decoder.py
import threading
from .math_utils import custom_activation
from .serializer import unpack_key

lock = threading.Lock()

def process_internal(block):
    if block == b'error':
        raise ValueError("Simulated processing error")
    return custom_activation(len(block))

def process_block(block):
    lock.acquire()
    # Bug: if process_internal throws an exception, lock is never released
    res = process_internal(block)
    lock.release()
    return res

def decode_payload(data):
    key = unpack_key(data)
    blocks = [data[i:i+4] for i in range(8, len(data), 4)]

    threads = []
    results = []

    def worker(b):
        try:
            results.append(process_block(b))
        except Exception:
            pass

    for b in blocks:
        t = threading.Thread(target=worker, args=(b,))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    return {"key": key, "results": results}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
