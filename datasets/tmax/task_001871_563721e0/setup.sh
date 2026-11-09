#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > validator.h
#ifndef VALIDATOR_H
#define VALIDATOR_H
int check_rate_limit(int tokens, int max_tokens);
#endif
EOF

    cat << 'EOF' > validator.c
#include "validator.h"

int check_rate_limit(int tokens, int max_tokens) {
    if (tokens <= max_tokens) {
        return 1;
    }
    return 0;
}
EOF

    cat << 'EOF' > limits.json
{
  "/api/login": 5,
  "/api/data": 100,
  "/api/admin": 1
}
EOF

    cat << 'EOF' > requests.json
[
  {"endpoint": "/api/login", "tokens": 3},
  {"endpoint": "/api/login", "tokens": 6},
  {"endpoint": "/api/data", "tokens": 50},
  {"endpoint": "/api/admin", "tokens": 2}
]
EOF

    cat << 'EOF' > processor.py
import json
import ctypes
import os

# TODO: Fix library path
lib = ctypes.CDLL("./libvalidator.so")

# TODO: Set argtypes and restype
# lib.check_rate_limit.argtypes = [ctypes.c_int, ctypes.c_int]
# lib.check_rate_limit.restype = ctypes.c_int

# TODO: Fix file paths
with open('limits.json', 'r') as f:
    limits = json.load(f)

with open('requests.json', 'r') as f:
    requests = json.load(f)

results = []
for req in requests:
    ep = req["endpoint"]
    tok = req["tokens"]
    max_tok = limits.get(ep, 0)

    allowed = lib.check_rate_limit(tok, max_tok)
    results.append({"endpoint": ep, "allowed": bool(allowed)})

with open('results.json', 'w') as f:
    json.dump(results, f)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
