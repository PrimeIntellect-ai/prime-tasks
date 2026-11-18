#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the C library source
    cat << 'EOF' > filter.c
#include <string.h>
int check_valid_api(const char* input) {
    if (input == NULL) return 0;
    if (strstr(input, "API_VALID") != NULL) return 1;
    return 0;
}
EOF

    # Compile the shared library
    gcc -shared -o libfilter.so -fPIC filter.c

    # Create the JSON data file
    cat << 'EOF' > data.json
[
  {"id": 101, "payload": "QQBQAEkAXwBWAEEATABJAEQAXwBUAEUAUwBUAA=="},
  {"id": 102, "payload": "SQBOAFYAQQBMAEkARABfAEQAQQBUAEEA"},
  {"id": 103, "payload": "QQBQAEkAXwBWAEEATABJAEQA"}
]
EOF

    # Create the broken process.py
    cat << 'EOF' > process.py
import json
import ctypes
import base64

# Load the shared library
lib = ctypes.CDLL('/home/user/libfilter.so')

# BUG 1: Missing/wrong ABI definitions
# lib.check_valid_api.argtypes = [...]
# lib.check_valid_api.restype = ...

with open('/home/user/data.json', 'r') as f:
    data = json.load(f)

results = []
for item in data:
    # BUG 2: Incorrect decoding pipeline
    raw_bytes = base64.b64decode(item['payload'])

    # Passing raw UTF-16-LE bytes directly to a C function expecting UTF-8
    if lib.check_valid_api(raw_bytes):
        results.append(item['id'])

with open('/home/user/result.json', 'w') as f:
    json.dump(results, f)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
