#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc git rustc cargo curl
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char hex[1024];
    if (!fgets(hex, sizeof(hex), stdin)) return 1;

    unsigned char buf[512];
    size_t len = 0;
    for (size_t i = 0; i < strlen(hex) - 1; i += 2) {
        sscanf(hex + i, "%2hhx", &buf[len++]);
    }

    if (len < 6) { printf("{\"error\":\"too short\"}\n"); return 1; }

    int version = buf[0];
    char device_id[256] = {0};
    int id_len = 0;
    size_t idx = 1;
    while (idx < len && buf[idx] != 0 && id_len < 255) {
        if (buf[idx] > 127) device_id[id_len++] = '?';
        else device_id[id_len++] = buf[idx];
        idx++;
    }
    idx++; // skip null

    if (idx + 4 > len) { printf("{\"error\":\"missing metric\"}\n"); return 1; }
    unsigned int metric = (buf[idx] << 24) | (buf[idx+1] << 16) | (buf[idx+2] << 8) | buf[idx+3];

    printf("{\"version\":%d,\"device_id\":\"%s\",\"metric\":%u}\n", version, device_id, metric);
    return 0;
}
EOF
gcc -O3 -s /app/oracle.c -o /app/telemetry_oracle
rm /app/oracle.c

mkdir -p /home/user/telemetry_svc/src
cd /home/user/telemetry_svc
git init

cat << 'EOF' > Cargo.toml
[package]
name = "telemetry_svc"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > src/main.rs
use std::io::{Read, Write};
use std::net::TcpListener;

fn parse_telemetry(buf: &[u8]) -> Result<String, &'static str> {
    if buf.len() < 6 { return Err("too short"); }
    let version = buf[0];
    let mut id_end = 1;
    while id_end < buf.len() && buf[id_end] != 0 {
        id_end += 1;
    }

    // GOOD behavior: replace invalid utf8
    let device_id = String::from_utf8_lossy(&buf[1..id_end]).replace("\u{FFFD}", "?");

    let idx = id_end + 1;
    if idx + 4 > buf.len() { return Err("missing metric"); }

    let metric = u32::from_be_bytes([buf[idx], buf[idx+1], buf[idx+2], buf[idx+3]]);

    let lb = '{';
    let rb = '}';
    Ok(format!("{}\"version\":{},\"device_id\":\"{}\",\"metric\":{}{}", lb, version, device_id, metric, rb))
}

fn main() {
    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();
    for stream in listener.incoming() {
        if let Ok(mut stream) = stream {
            let mut buf = [0; 1024];
            if let Ok(n) = stream.read(&mut buf) {
                // simple http parsing skip
                let req = &buf[..n];
                if let Some(body_start) = req.windows(4).position(|w| w == b"\r\n\r\n") {
                    let body = &req[body_start+4..];
                    match parse_telemetry(body) {
                        Ok(json) => {
                            let res = format!("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}", json.len(), json);
                            let _ = stream.write_all(res.as_bytes());
                        }
                        Err(_) => {
                            let _ = stream.write_all(b"HTTP/1.1 500 ERR\r\n\r\n");
                        }
                    }
                }
            }
        }
    }
}
EOF

git add Cargo.toml src/main.rs
git config user.email "test@example.com"
git config user.name "Test User"
git commit -m "Initial commit"
git tag v1.0.0

for i in $(seq 1 200); do
    if [ $i -eq 145 ]; then
        sed -i 's/String::from_utf8_lossy(&buf\[1..id_end\]).replace("\\u{FFFD}", "?")/std::str::from_utf8(\&buf\[1..id_end\]).unwrap().to_string()/' src/main.rs
        git commit -am "Refactor parsing to avoid allocations"
    else
        echo "// dummy comment $i" >> src/main.rs
        git commit -am "Dummy commit $i"
    fi
done

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
