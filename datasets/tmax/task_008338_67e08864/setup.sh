#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/libcalc.c
#include <string.h>
#include <stdlib.h>

int process_data(const char* input) {
    char buffer[11];
    // Vulnerability: strcpy doesn't check bounds
    strcpy(buffer, input);

    int sum = 0;
    for(int i=0; i<strlen(buffer); i++) {
        sum += (unsigned char)buffer[i];
    }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/app/api.py
import ctypes
import json

lib = ctypes.CDLL('./libcalc.so')
lib.process_data.argtypes = [ctypes.c_char_p]
lib.process_data.restype = ctypes.c_int

def run_server():
    with open('requests.json', 'r') as f:
        requests = json.load(f)

    # TODO: Add rate limiting (max 2 requests per user)
    # TODO: Add request validation (data must be strictly alphanumeric)
    # TODO: Write results to results.log

    for req in requests:
        user = req['user']
        data = req['data']

        # Python 2 string handling -> needs update for Py3
        res = lib.process_data(data)
        print "Processed user:", user

if __name__ == '__main__':
    run_server()
EOF

    cat << 'EOF' > /home/user/app/requests.json
[
    {"user": "alice", "data": "abcd"},
    {"user": "bob", "data": "123456789012345"},
    {"user": "alice", "data": "a b c"},
    {"user": "charlie", "data": "xyz"},
    {"user": "bob", "data": "test"},
    {"user": "alice", "data": "valid"},
    {"user": "alice", "data": "overflow"}
]
EOF

    cd /home/user/app
    gcc -shared -fPIC libcalc.c -o libcalc.so

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
