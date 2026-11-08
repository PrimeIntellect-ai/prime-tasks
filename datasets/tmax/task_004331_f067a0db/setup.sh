#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git supervisor logrotate curl build-essential
    pip3 install pytest

    # Install Rust minimal profile
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /home/user/app/logs /home/user/git/alerts.git /home/user/app/rust_monitor/src
    git init --bare /home/user/git/alerts.git

    # Generate 500k dummy log lines
    python3 -c '
with open("/home/user/app/logs/access.log", "w") as f:
    f.writelines(["INFO: Request processed smoothly\n"] * 499500)
    f.writelines(["ERROR: Critical failure detected\n"] * 500)
'

    # Create naive Rust project
    cat << 'EOF' > /home/user/app/rust_monitor/Cargo.toml
[package]
name = "rust_monitor"
version = "0.1.0"
edition = "2021"

[dependencies]
reqwest = { version = "0.11", features = ["blocking"] }
EOF

    cat << 'EOF' > /home/user/app/rust_monitor/src/main.rs
fn main() {
    println!("Naive Rust implementation");
}
EOF

    # Create web_server.py
    cat << 'EOF' > /home/user/app/web_server.py
import time
import sys

def main():
    while True:
        with open("/home/user/app/logs/access.log", "a") as f:
            f.write("INFO: Request processed smoothly\n")
        time.sleep(2)

if __name__ == "__main__":
    main()
EOF

    # Create git_auditor.py
    cat << 'EOF' > /home/user/app/git_auditor.py
import os
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode('utf-8')

        repo = "/home/user/git/alerts.git"
        env = os.environ.copy()
        env['GIT_DIR'] = repo
        env['GIT_WORK_TREE'] = '/tmp'
        env['GIT_AUTHOR_NAME'] = 'Auditor'
        env['GIT_AUTHOR_EMAIL'] = 'auditor@local'
        env['GIT_COMMITTER_NAME'] = 'Auditor'
        env['GIT_COMMITTER_EMAIL'] = 'auditor@local'

        subprocess.run(["git", "commit", "--allow-empty", "-m", post_data], env=env)

        self.send_response(200)
        self.end_headers()

if __name__ == "__main__":
    HTTPServer(('127.0.0.1', 8080), Handler).serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
