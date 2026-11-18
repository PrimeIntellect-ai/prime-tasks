#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cargo rustc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.py
import sys, json, base64, urllib.parse
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    payload = data['payload']
    decoded_url = urllib.parse.unquote(payload)
    decoded_b64 = base64.b64decode(decoded_url).decode('utf-8')
    if "<script>" in decoded_b64 or "DROP TABLE" in decoded_b64 or "admin=true" in decoded_b64:
        sys.exit(1)
    sys.exit(0)
except:
    sys.exit(1)
EOF

    cat << 'EOF' > /app/wrapper.cpp
#include <cstdlib>
#include <string>
int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::string cmd = std::string("python3 /app/oracle.py \"") + argv[1] + "\"";
    int res = std::system(cmd.c_str());
    return WEXITSTATUS(res);
}
EOF
    g++ -O2 /app/wrapper.cpp -o /app/legacy_gate
    strip /app/legacy_gate

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/corpora/clean /home/user/corpora/evil

    cat << 'EOF' > /tmp/gen_corpora.py
import os, json, base64, urllib.parse

for i in range(50):
    text_clean = f"clean telemetry data {i}"
    b64_clean = base64.b64encode(text_clean.encode()).decode()
    url_clean = urllib.parse.quote(b64_clean)
    with open(f'/home/user/corpora/clean/file_{i}.json', 'w') as f:
        json.dump({"payload": url_clean}, f)

    evil_str = ["<script>", "DROP TABLE", "admin=true"][i % 3]
    text_evil = f"evil telemetry data {i} {evil_str}"
    b64_evil = base64.b64encode(text_evil.encode()).decode()
    url_evil = urllib.parse.quote(b64_evil)
    with open(f'/home/user/corpora/evil/file_{i}.json', 'w') as f:
        json.dump({"payload": url_evil}, f)
EOF
    python3 /tmp/gen_corpora.py

    mkdir -p /home/user/telemetry_gate/src
    cat << 'EOF' > /home/user/telemetry_gate/Cargo.toml
[package]
name = "telemetry_gate"
version = "0.1.0"
edition = "2021"

[dependencies]
serde_json = "1.0"
base64 = "0.21"
urlencoding = "2.1"
EOF

    cat << 'EOF' > /home/user/telemetry_gate/src/main.rs
use std::env;
use std::fs;

fn decode_payload<'a>(payload: &'a String) -> &'a str {
    let url_decoded = urlencoding::decode(payload).unwrap().into_owned();
    let b64_decoded = String::from_utf8(base64::decode(url_decoded).unwrap()).unwrap();
    &b64_decoded
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        std::process::exit(1);
    }
    let content = fs::read_to_string(&args[1]).unwrap();
    let v: serde_json::Value = serde_json::from_str(&content).unwrap();
    let payload = v["payload"].as_str().unwrap().to_string();

    let decoded = decode_payload(&payload);

    if decoded.contains("<script>") || decoded.contains("DROP TABLE") || decoded.contains("admin=true") {
        std::process::exit(1);
    }
}
EOF

    cat << 'EOF' > /home/user/run_benchmark.sh
#!/bin/bash
echo "Benchmarking..."
sleep 1
echo "Benchmark completed"
EOF
    chmod +x /home/user/run_benchmark.sh

    chmod -R 777 /home/user
