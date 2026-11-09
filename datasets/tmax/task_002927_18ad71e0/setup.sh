#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nodejs npm redis-server
    pip3 install pytest

    mkdir -p /app/cores
    mkdir -p /app/worker
    mkdir -p /app/oracle
    mkdir -p /app/api

    cat << 'EOF' > /app/worker/math_worker.cpp
#include <iostream>
#include <string>

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::string input = argv[1];
    long long hash = 0;
    // Buggy implementation causing segfault or wrong result
    for (size_t i = 0; i <= input.length(); ++i) {
        hash = (hash * 31 + input[i]) % 1000000007;
    }
    std::cout << hash << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /app/worker/config.ini
[queue]
queue_channel=tasks
EOF

    cat << 'EOF' > /app/oracle/reference_worker.py
#!/usr/bin/env python3
import sys

def compute_hash(s):
    h = 0
    for char in s:
        h = (h * 31 + ord(char)) % 1000000007
    return h

if __name__ == '__main__':
    if len(sys.argv) > 1:
        print(compute_hash(sys.argv[1]))
EOF
    chmod +x /app/oracle/reference_worker.py

    cat << 'EOF' > /app/api/server.js
const express = require('express');
const redis = require('redis');
require('dotenv').config();

const app = express();
app.use(express.json());

const client = redis.createClient({
    port: process.env.REDIS_PORT || 6379
});

app.post('/compute', (req, res) => {
    // Dummy implementation
    res.send("OK");
});

app.listen(3000, () => {
    console.log('API listening on port 3000');
});
EOF

    cat << 'EOF' > /app/api/.env
REDIS_PORT=6380
REDIS_CHANNEL=tasks
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
