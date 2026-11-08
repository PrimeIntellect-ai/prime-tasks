#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

    # Install dependencies
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest Flask==2.2.5 Werkzeug==2.2.3

    # Create required directories
    mkdir -p /home/user/sensor_api
    mkdir -p /app

    # Create the buggy app.py
    cat << 'EOF' > /home/user/sensor_api/app.py
from flask import Flask, request, jsonify
import subprocess

app = Flask(__name__)

@app.route('/process', methods=['POST'])
def process():
    req = request.json
    sensor_id = req['sensor_id']
    data = req['data']

    # Bug 1: No validation of data types, crashes on "err" or null
    mean = sum(data) / len(data)

    # Bug 2: Numerical instability
    variance = sum((x - mean)**2 for x in data) / len(data)
    inverse_variance = 1.0 / variance 

    # Bug 3: Incorrect invocation of binary (doesn't format properly, doesn't pad/truncate)
    cmd = ["/app/calc_baseline"] + [str(x) for x in data]
    result = subprocess.run(cmd, capture_output=True, text=True)
    baseline = float(result.stdout.strip())

    final_score = inverse_variance * baseline
    return jsonify({"sensor_id": sensor_id, "final_score": final_score})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

    # Create requirements.txt
    cat << 'EOF' > /home/user/sensor_api/requirements.txt
Flask==2.2.5
Werkzeug==2.2.3
EOF

    # Create and compile the binary
    cat << 'EOF' > /tmp/calc_baseline.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 6) {
        return 1;
    }
    float f1 = atof(argv[1]);
    float f2 = atof(argv[2]);
    float f3 = atof(argv[3]);
    float f4 = atof(argv[4]);
    float f5 = atof(argv[5]);
    float result = (f1 * 0.1) + (f2 * 0.2) + (f3 * 0.3) + (f4 * 0.4) + (f5 * 0.5);
    printf("%.4f\n", result);
    return 0;
}
EOF
    gcc -O2 /tmp/calc_baseline.c -o /app/calc_baseline
    strip /app/calc_baseline
    rm /tmp/calc_baseline.c
    chmod +x /app/calc_baseline

    # Create the user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chown -R user:user /home/user/sensor_api
    chmod -R 777 /home/user
