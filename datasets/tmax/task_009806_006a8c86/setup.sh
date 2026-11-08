#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/math_build

    cat << 'EOF' > /home/user/math_build/factorizer.py
import math
import threading
import json
import base64

results = []

def factorize(n):
    factors = []
    # Bug 1: off by one (missing + 1)
    for i in range(2, int(math.sqrt(n))):
        while n % i == 0:
            factors.append(i)
            n //= i
    if n > 1:
        factors.append(n)
    return factors

def worker(n):
    f = factorize(n)
    global results
    # Bug 2: Race condition
    current = results[:]
    current.append({n: f})
    results = current

def process_numbers(numbers):
    global results
    results = []
    threads = []
    for n in numbers:
        t = threading.Thread(target=worker, args=(n,))
        threads.append(t)
        t.start()
    for t in threads:
        t.join()

    # Sort deterministically
    results.sort(key=lambda x: list(x.keys())[0])

    # Bug 3: Encoding bug (json.dumps needs string keys, dicts with int keys get converted to string keys by json, but let's introduce a serialization bug: encoding a string as utf-16 before base64 instead of utf-8, or trying to encode dict directly)
    json_str = json.dumps(results)
    # Incorrect encoding step
    return base64.b64encode(json_str.encode('utf-16')).decode('ascii')
EOF

    cat << 'EOF' > /home/user/math_build/test_build.py
from factorizer import process_numbers
import base64
import json

def test_factorizer():
    res = process_numbers([9])
    decoded = json.loads(base64.b64decode(res).decode('utf-8'))
    assert decoded == [{"9": [3, 3]}], f"Failed: {decoded}"
    print("Test passed.")

if __name__ == "__main__":
    test_factorizer()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
