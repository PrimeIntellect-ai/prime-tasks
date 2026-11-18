#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make nginx curl file
    pip3 install pytest flask requests

    mkdir -p /home/user/app
    cd /home/user/app

    cat << 'EOF' > libcalc.c
int calculate(int n) {
    return n * 2;
}
EOF

    cat << 'EOF' > Makefile
libcalc.so: libcalc.c
	gcc -o libcalc.so libcalc.c
EOF

    cat << 'EOF' > api.py
import ctypes
from flask import Flask, request

app = Flask(__name__)
history = []

try:
    lib = ctypes.CDLL('./libcalc.so')
except OSError as e:
    lib = None

@app.route('/compute')
def compute():
    val = int(request.args.get('val', 0))
    if not lib:
        return "Linking Error", 500
    res = lib.calculate(val)
    history.append('x' * 1024 * 1024) # Intentionally leak ~1MB per request
    return str(res)

if __name__ == '__main__':
    app.run(port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
