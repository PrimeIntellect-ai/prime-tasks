#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo curl
    pip3 install pytest

    mkdir -p /home/user/rust_encoder/src

    cat << 'EOF' > /home/user/rust_encoder/Cargo.toml
[package]
name = "rust_encoder"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/rust_encoder/src/main.rs
fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 { std::process::exit(1); }
    let message = args[1].clone();
    let shift: u32 = args[2].parse().unwrap();

    let mut result = String::new();
    let r = &result; 
    for c in message.chars() {
        let val = c as u32;
        let shifted = val + shift.pow(2);
        let new_c = std::char::from_u32(shifted).unwrap_or('?');
        result.push(new_c);
    }
    println!("{}", r);
}
EOF

    cat << 'EOF' > /home/user/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.parse
import subprocess

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/encode":
            self.send_response(404)
            self.end_headers()
            return

        qs = urllib.parse.parse_qs(parsed.query)
        msg = qs.get('msg', [''])[0]
        # Bug: incorrectly named parameter
        shift = qs.get('shft', [''])[0]

        if not msg or not shift:
            self.send_response(400)
            self.end_headers()
            return

        res = subprocess.run(
            ['/home/user/rust_encoder/target/debug/rust_encoder', msg, shift],
            capture_output=True, text=True
        )

        self.send_response(200)
        self.send_header('Content-type', 'text/plain; charset=utf-8')
        self.end_headers()
        self.wfile.write(res.stdout.strip().encode('utf-8'))

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), Handler)
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
