#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gcc build-essential
    pip3 install pytest requests

    # Install Node.js
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    # Create directories
    mkdir -p /app/node_api
    mkdir -p /app/c_lib
    mkdir -p /app/proxy

    # Create files
    cat << 'EOF' > /app/node_api/package.json
{
  "name": "node_api",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5"
  },
  "peerDependencies": {
    "body-parser": "1.19.0"
  },
  "devDependencies": {
    "body-parser": "1.20.0"
  }
}
EOF

    cat << 'EOF' > /app/node_api/index.js
const express = require('express');
const app = express();
app.get('*', (req, res) => res.send('API_SUCCESS'));
app.listen(3001, '127.0.0.1');
EOF

    cat << 'EOF' > /app/c_lib/hasher.c
#include <stdint.h>
uint32_t hash_api_key(const char* key) {
    uint32_t hash = 5381;
    int c;
    while ((c = *key++)) {
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
    }
    return hash;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
