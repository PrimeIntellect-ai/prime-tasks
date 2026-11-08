#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl nginx redis-server build-essential
    pip3 install pytest flask redis

    # Install Rust for building the oracle and for the agent
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    # Create oracle directory
    mkdir -p /opt/oracle/src

    # Write the oracle source code
    cat << 'EOF' > /opt/oracle/src/main.rs
use std::io::{self, Read};

fn hash_fnv1a(token: &str) -> u32 {
    let mut hash: u32 = 2166136261;
    for byte in token.bytes() {
        hash ^= byte as u32;
        hash = hash.wrapping_mul(16777619);
    }
    hash
}

fn main() {
    let mut input = String::new();
    if io::stdin().read_to_string(&mut input).is_err() {
        println!("[]");
        return;
    }

    // 1. HTML Stripping
    let mut stripped = String::new();
    let mut in_tag = false;
    for c in input.chars() {
        if c == '<' {
            in_tag = true;
        } else if c == '>' && in_tag {
            in_tag = false;
        } else if !in_tag {
            stripped.push(c);
        }
    }

    // 2. Lowercasing
    let lowercased = stripped.to_lowercase();

    // 3. Punctuation Removal (Retain ONLY A-Z, a-z, 0-9 and spaces)
    let mut cleaned = String::new();
    for c in lowercased.chars() {
        if c.is_ascii_alphanumeric() || c == ' ' {
            cleaned.push(c);
        }
    }

    // 4. Tokenization & 5. Numerical Hashing
    let mut tokens = Vec::new();
    for token in cleaned.split_whitespace() {
        tokens.push(hash_fnv1a(token));
    }

    // 6. Output
    println!("{:?}", tokens);
}
EOF

    # Compile oracle
    cd /opt/oracle
    rustc src/main.rs -o tokenizer_oracle
    chmod +x tokenizer_oracle

    # Create user and pipeline directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pipeline

    # Write nginx.conf
    cat << 'EOF' > /home/user/pipeline/nginx.conf
worker_processes 1;
error_log /tmp/error.log;
pid /tmp/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /tmp/access.log;
    client_body_temp_path /tmp/client_body;
    fastcgi_temp_path /tmp/fastcgi_temp;
    proxy_temp_path /tmp/proxy_temp;
    scgi_temp_path /tmp/scgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;

    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5001;
        }
    }
}
EOF

    # Write api.py
    cat << 'EOF' > /home/user/pipeline/api.py
from flask import Flask, request, jsonify
import redis
import subprocess
import json

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6380)

@app.route('/tokenize', methods=['POST'])
def tokenize():
    data = request.json
    text = data.get('text', '')

    try:
        process = subprocess.Popen(['/home/user/bin/tokenizer'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = process.communicate(input=text)
        tokens = json.loads(stdout)
        r.rpush('tokenized_results', json.dumps(tokens))
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Ensure Rust is available for the user
    su - user -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"

    chmod -R 777 /home/user
