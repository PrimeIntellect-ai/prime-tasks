#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nodejs npm cargo curl
    pip3 install pytest

    mkdir -p /home/user/app/verifier/src
    mkdir -p /home/user/app/gateway
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /home/user/app/verifier/Cargo.toml
[package]
name = "verifier"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/app/verifier/src/main.rs
fn main() {
    // TODO: implement verifier
}
EOF

    cat << 'EOF' > /home/user/app/gateway/package.json
{
  "name": "gateway",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "redis": "^4.6.7"
  }
}
EOF

    cat << 'EOF' > /home/user/app/gateway/index.js
const express = require('express');
const redis = require('redis');
const fs = require('fs');
const { execFileSync } = require('child_process');

const app = express();
app.use(express.text({ type: '*/*' }));

const redisClient = redis.createClient();
redisClient.connect().catch(console.error);

app.post('/submit', async (req, res) => {
    const manifest = req.body;
    // TODO: Validate via Rust and push to Redis
    res.status(500).send("Not implemented");
});

app.listen(8080, () => {
    console.log('Gateway listening on port 8080');
});
EOF

    cd /home/user/app/gateway && npm install

    for i in $(seq 1 10); do
        cat << EOF > /home/user/corpora/clean/clean_$i.txt
APP: App$i
VERSION: 1.0.0
DEPS:
  - pkg: libA, ver: >=1.0.0, resolved: 1.0.1
  - pkg: libB, ver: ^2.1.0, resolved: 2.1.5
END
EOF
    done

    for i in $(seq 1 15); do
        cat << EOF > /home/user/corpora/evil/evil_$i.txt
APP: EvilApp$i
VERSION: 1.0.0
DEPS:
  - pkg: libA, ver: >=1.0.0, resolved: 0.9.9
END
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
