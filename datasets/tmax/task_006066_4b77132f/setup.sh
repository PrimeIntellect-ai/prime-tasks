#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/artifact_cache/verifier/src
    mkdir -p /home/user/artifact_cache/backend_storage/artifacts

    cat << 'EOF' > /home/user/artifact_cache/verifier/Cargo.toml
[package]
name = "verifier"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /home/user/artifact_cache/verifier/src/main.rs
use std::env;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        process::exit(1);
    }

    // BUG: Cannot move out of index of `Vec<String>`
    let artifact = args[1]; 

    if artifact.starts_with("core-") {
        process::exit(0);
    } else {
        process::exit(1);
    }
}
EOF

    cat << 'EOF' > /home/user/artifact_cache/proxy.py
import sys
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.request
import urllib.error

class ProxyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # TODO: Implement reverse proxy logic here
        pass

def run(server_class=HTTPServer, handler_class=ProxyHandler, port=8080):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    httpd.serve_forever()

if __name__ == '__main__':
    run()
EOF

    cat << 'EOF' > /home/user/artifact_cache/test_proxy.py
import pytest
import urllib.request
import urllib.error
import threading
from http.server import HTTPServer, SimpleHTTPRequestHandler
import os
from proxy import ProxyHandler

# TODO: Implement `mock_backend` fixture
# TODO: Implement `proxy_server` fixture

def test_valid_artifact_proxied(mock_backend, proxy_server):
    req = urllib.request.Request("http://localhost:8080/download/core-linux.tar.gz")
    with urllib.request.urlopen(req) as response:
        assert response.status == 200
        assert response.read().decode('utf-8').strip() == "dummy-data"

def test_invalid_artifact_rejected(mock_backend, proxy_server):
    req = urllib.request.Request("http://localhost:8080/download/malicious.sh")
    try:
        urllib.request.urlopen(req)
    except urllib.error.HTTPError as e:
        assert e.code == 403
        assert e.read().decode('utf-8') == "Invalid artifact"
EOF

    echo "dummy-data" > /home/user/artifact_cache/backend_storage/artifacts/core-linux.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
