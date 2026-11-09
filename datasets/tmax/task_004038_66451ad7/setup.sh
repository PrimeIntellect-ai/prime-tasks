#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential redis-server curl
    pip3 install pytest flask redis python-dotenv requests

    mkdir -p /app/ext /app/api /app/worker /app/bin /app/config

    # 1. C++ Extension
    cat << 'EOF' > /app/ext/math_core.cpp
#include <cmath>
extern "C" {
    double process_math(double input) {
        return std::sin(input) * std::cos(input);
    }
}
EOF

    cat << 'EOF' > /app/ext/Makefile
all: math_core.so

math_core.so: math_core.cpp
	g++ -shared -fPIC -o math_core.so math_core.cpp
EOF

    # 2. Binary Generator
    cat << 'EOF' > /tmp/telemetry_gen.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char** argv) {
    int count = 1;
    if (argc > 1) count = atoi(argv[1]);
    for (int i=0; i<count; i++) {
        uint32_t magic = 0xDEADBEEF;
        uint16_t len = (i % 2 == 0) ? 10 : 300;
        fwrite(&magic, 1, 4, stdout);
        if (len > 255) {
            uint16_t be_len = (len >> 8) | (len << 8);
            fwrite(&be_len, 1, 2, stdout);
        } else {
            fwrite(&len, 1, 2, stdout);
        }
        for(int j=0; j<len; j++) {
            uint8_t b = (uint8_t)(j % 256);
            fwrite(&b, 1, 1, stdout);
        }
    }
    return 0;
}
EOF
    gcc -o /app/bin/telemetry_gen /tmp/telemetry_gen.c
    chmod +x /app/bin/telemetry_gen

    # 3. API
    cat << 'EOF' > /app/api/parser.py
import struct

def parse_telemetry(data):
    if len(data) < 6: return None
    magic = data[:4]
    length = struct.unpack('<H', data[4:6])[0]
    payload = data[6:6+length]
    return payload
EOF

    cat << 'EOF' > /app/api/app.py
from flask import Flask, request
import redis
import os
from parser import parse_telemetry

app = Flask(__name__)
r = redis.Redis(host=os.getenv('REDIS_HOST', 'wronghost'), port=int(os.getenv('REDIS_PORT', 9999)))

@app.route('/process', methods=['POST'])
def process():
    data = request.get_data()
    payload = parse_telemetry(data)
    job_id = request.headers.get('X-Job-Id', '0')
    if payload:
        r.lpush('math_jobs', f"{job_id}:{len(payload)}")
    return "OK"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    cat << 'EOF' > /app/api/.env
REDIS_HOST=wronghost
REDIS_PORT=9999
EOF

    # 4. Worker
    cat << 'EOF' > /app/worker/worker.py
import redis
import os
import ctypes
import time

r = redis.Redis(host=os.getenv('REDIS_HOST', 'wronghost'), port=int(os.getenv('REDIS_PORT', 9999)))

try:
    math_lib = ctypes.CDLL('/app/ext/math_core.so')
    math_lib.process_math.argtypes = [ctypes.c_double]
    math_lib.process_math.restype = ctypes.c_double
except:
    math_lib = None

def work():
    while True:
        job = r.brpop('math_jobs', timeout=1)
        if job and math_lib:
            _, data = job
            job_id, val = data.decode().split(':')
            res = math_lib.process_math(float(val))
            r.set(f"result:{job_id}", res)
        time.sleep(0.1)

if __name__ == '__main__':
    work()
EOF

    cat << 'EOF' > /app/worker/.env
REDIS_HOST=wronghost
REDIS_PORT=9999
EOF

    # 5. Scripts
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
cd /app/api && export $(cat .env | xargs) && python3 app.py &
cd /app/worker && export $(cat .env | xargs) && python3 worker.py &
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/evaluate.py
import subprocess
import requests
import redis
import time
import json

def run():
    r = redis.Redis(host='localhost', port=6379)
    try:
        r.ping()
    except:
        pass

    # Evaluate logic here...
    result = {"accuracy": 0.0}
    with open('/home/user/evaluation_result.json', 'w') as f:
        json.dump(result, f)

if __name__ == '__main__':
    run()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
