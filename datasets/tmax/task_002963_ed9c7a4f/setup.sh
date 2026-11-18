#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential openssl bc procps
    pip3 install pytest

    mkdir -p /app/vendor/secure_etl_tool-1.0
    mkdir -p /app/certs

    # Create Makefile
    cat << 'EOF' > /app/vendor/secure_etl_tool-1.0/Makefile
PYTHON_INCLUDES=-I/usr/include/python2.7
all:
	gcc -shared -o fast_integrity.so -fPIC fast_integrity.c $(PYTHON_INCLUDES)
EOF

    # Create fast_integrity.c
    cat << 'EOF' > /app/vendor/secure_etl_tool-1.0/fast_integrity.c
#include <Python.h>

static PyObject* verify(PyObject* self, PyObject* args) {
    Py_RETURN_TRUE;
}

static PyMethodDef FastIntegrityMethods[] = {
    {"verify", verify, METH_VARARGS, "Verify integrity"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fast_integrity_module = {
    PyModuleDef_HEAD_INIT,
    "fast_integrity",
    NULL,
    -1,
    FastIntegrityMethods
};

PyMODINIT_FUNC PyInit_fast_integrity(void) {
    return PyModule_Create(&fast_integrity_module);
}
EOF

    # Create worker.py
    cat << 'EOF' > /app/vendor/secure_etl_tool-1.0/worker.py
import subprocess
import time
import os
import sys

try:
    import fast_integrity
    C_EXT_LOADED = True
except ImportError:
    C_EXT_LOADED = False

def process_logs():
    secret_key = "supersecret"

    # Insecure subprocess call leaking password to command line
    cmd = ["openssl", "enc", "-d", "-aes-256-cbc", "-pass", f"pass:{secret_key}", "-in", "/dev/null", "-out", "/dev/null"]

    # Execute the command (in background to simulate processing)
    p = subprocess.Popen(cmd, stderr=subprocess.DEVNULL)

    # Simulate processing 5000 logs
    for i in range(5000):
        if C_EXT_LOADED:
            pass # Fast C-extension
        else:
            time.sleep(0.005) # Slow Python fallback

    p.wait()

if __name__ == "__main__":
    process_logs()
EOF

    # Create config.json
    cat << 'EOF' > /app/vendor/secure_etl_tool-1.0/config.json
{
    "cert_path": "/app/certs/client.pem"
}
EOF

    # Create dummy cert
    touch /app/certs/client.pem

    # Create user and home directory
    useradd -m -s /bin/bash user || true

    # Create run_benchmark.sh
    cat << 'EOF' > /home/user/run_benchmark.sh
#!/bin/bash
cd /app/vendor/secure_etl_tool-1.0/

rm -f /tmp/leak_detected

# Start a background process that monitors for leaks
(
    for i in {1..30}; do
        if ps -ef | grep "pass:" | grep -v grep > /dev/null; then
            touch /tmp/leak_detected
        fi
        sleep 0.1
    done
) &
MONITOR_PID=$!

START=$(date +%s.%N)
python3 worker.py
END=$(date +%s.%N)
DUR=$(echo "$END - $START" | bc)

wait $MONITOR_PID

if [ -f /tmp/leak_detected ]; then
    echo "0.0" > /home/user/benchmark_result.txt
else
    # Calculate logs per second
    SCORE=$(echo "5000 / $DUR" | bc -l)
    echo "$SCORE" > /home/user/benchmark_result.txt
fi
EOF
    chmod +x /home/user/run_benchmark.sh

    # Create verify_metric.py
    cat << 'EOF' > /home/user/verify_metric.py
import sys

try:
    with open("/home/user/benchmark_result.txt", "r") as f:
        score = float(f.read().strip())
    if score >= 250.0:
        print("Success")
        sys.exit(0)
    else:
        print("Fail")
        sys.exit(1)
except Exception:
    sys.exit(1)
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
