#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-dev \
        python3-setuptools \
        build-essential \
        gcc \
        redis-server

    pip3 install pytest flask redis gunicorn

    mkdir -p /app/processor/ext

    cat << 'EOF' > /app/redis.conf
port 6379
bind 127.0.0.1
daemonize no
EOF

    cat << 'EOF' > /app/ingestor.py
import socketserver
import json
import redis

r = redis.Redis(host='127.0.0.1', port=6379, db=0)

class LogHandler(socketserver.BaseRequestHandler):
    def handle(self):
        data = self.request.recv(1024)
        if not data:
            return

        text = data.decode('utf-8')
        obj = json.loads(text)
        r.lpush('logs', json.dumps(obj))

if __name__ == "__main__":
    server = socketserver.TCPServer(("127.0.0.1", 5000), LogHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /app/processor/app.py
from flask import Flask, jsonify
import redis
import json
import sys
import os

sys.path.append(os.path.join(os.path.dirname(__file__), 'ext'))
try:
    import entropy_ext
except ImportError:
    entropy_ext = None

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/stats')
def stats():
    valid_logs_processed = r.llen('logs')
    dead_letters = r.llen('dead_letter')

    latest_entropy = 0.0
    if valid_logs_processed > 0:
        latest_log_raw = r.lindex('logs', 0)
        if latest_log_raw:
            latest_log = json.loads(latest_log_raw)
            msg = latest_log.get('message', '')
            if entropy_ext:
                latest_entropy = entropy_ext.calculate_entropy(msg)
            else:
                latest_entropy = -1.0

    return jsonify({
        "valid_logs_processed": valid_logs_processed,
        "dead_letters": dead_letters,
        "latest_entropy": latest_entropy
    })

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8000)
EOF

    cat << 'EOF' > /app/processor/ext/setup.py
from setuptools import setup, Extension

module = Extension('entropy_ext', sources=['entropy.c'])

setup(name='entropy_ext',
      version='1.0',
      description='Calculate entropy',
      ext_modules=[module])
EOF

    cat << 'EOF' > /app/processor/ext/entropy.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <math.h>

static PyObject* calculate_entropy(PyObject* self, PyObject* args) {
    const char* message;
    if (!PyArg_ParseTuple(args, "s", &message)) {
        return NULL;
    }

    int counts[256] = {0};
    int len = 0;
    for (int i = 0; message[i] != '\0'; i++) {
        counts[(unsigned char)message[i]]++;
        len++;
    }

    double entropy = 0.0;
    if (len > 0) {
        for (int i = 0; i < 256; i++) {
            if (counts[i] > 0) {
                double prob = (double)counts[i] / len;
                entropy += prob * log(prob);
            }
        }
    }

    return PyFloat_FromDouble(entropy);
}

static PyMethodDef EntropyMethods[] = {
    {"calculate_entropy", calculate_entropy, METH_VARARGS, "Calculate Shannon entropy."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef entropymodule = {
    PyModuleDef_HEAD_INIT,
    "entropy_ext",
    NULL,
    -1,
    EntropyMethods
};

PyMODINIT_FUNC PyInit_entropy_ext(void) {
    return PyModule_Create(&entropymodule);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
