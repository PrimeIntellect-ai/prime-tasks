#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak python3-dev build-essential tcpdump
    pip3 install pytest scapy

    mkdir -p /app/transcriber_service/fast_filter

    # Generate the ground truth audio and XOR it
    cat << 'EOF' > /tmp/gen_audio.py
import subprocess
import os

text = "the server infrastructure migration is scheduled for next tuesday at midnight ensure all database backups are verified before initiating the sequence"
subprocess.run(['espeak', '-w', '/tmp/temp.wav', text], check=True)

with open('/tmp/temp.wav', 'rb') as f:
    data = bytearray(f.read())

for i in range(len(data)):
    data[i] ^= 0x3F

with open('/app/voicemail.wav', 'wb') as f:
    f.write(data)
EOF
    python3 /tmp/gen_audio.py

    # Generate the pcap file
    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import wrpcap, Ether, IP, UDP, Raw
packets = []
for _ in range(20):
    pkt = Ether()/IP(dst="10.0.0.5")/UDP(dport=8080)/Raw(load=b"\x3F\x00\x01\x02\x03\x04")
    packets.append(pkt)
wrpcap('/app/transcriber_service/capture.pcap', packets)
EOF
    python3 /tmp/gen_pcap.py

    # Create main.py with async memory leak
    cat << 'EOF' > /app/transcriber_service/main.py
import asyncio

async def process_chunk(chunk):
    await asyncio.sleep(0.1)

async def main():
    tasks = []
    for i in range(50):
        task = asyncio.create_task(process_chunk(i))
        tasks.append(task)
        # Simulated cancellation
        task.cancel()
        # Missing await task to clear the cancelled state

if __name__ == "__main__":
    asyncio.run(main())
EOF

    # Create requirements.txt with dependency conflict
    cat << 'EOF' > /app/transcriber_service/requirements.txt
requests==2.25.1
urllib3==1.26.5
chardet==3.0.4
idna==2.10
# Conflict: requests 2.25.1 requires urllib3<1.27,>=1.21.1
EOF

    # Create fast_filter C-extension
    cat << 'EOF' > /app/transcriber_service/fast_filter/filter.c
#include <Python.h>
#include <math.h>

static PyObject* apply_filter(PyObject* self, PyObject* args) {
    double value;
    if (!PyArg_ParseTuple(args, "d", &value)) {
        return NULL;
    }
    double result = sin(value) * cos(value);
    return PyFloat_FromDouble(result);
}

static PyMethodDef FilterMethods[] = {
    {"apply_filter", apply_filter, METH_VARARGS, "Apply noise filter"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef filtermodule = {
    PyModuleDef_HEAD_INIT,
    "fast_filter",
    "Fast audio filter",
    -1,
    FilterMethods
};

PyMODINIT_FUNC PyInit_fast_filter(void) {
    return PyModule_Create(&filtermodule);
}
EOF

    cat << 'EOF' > /app/transcriber_service/fast_filter/setup.py
from setuptools import setup, Extension

# Deliberately missing 'm' in libraries to cause linking error for math functions
module = Extension('fast_filter',
                    sources = ['filter.c'],
                    libraries = [])

setup(name = 'fast_filter',
      version = '1.0',
      description = 'Fast audio filter module',
      ext_modules = [module])
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
