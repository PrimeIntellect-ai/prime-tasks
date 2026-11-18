#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl cargo rustc ffmpeg python3-flask
    pip3 install pytest

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=5:size=640x360:rate=30 -pix_fmt yuv420p /app/video.mp4

    mkdir -p /home/user/fec_lib
    cat << 'EOF' > /home/user/fec_lib/fec.c
#include <stdint.h>
#include <stddef.h>

// A simple parity/FEC checksum
uint32_t compute_fec(const uint8_t* buffer, size_t length) {
    uint32_t checksum = 0;
    for (size_t i = 0; i < length; i++) {
        checksum ^= (buffer[i] << (i % 8));
    }
    return checksum;
}
EOF

    cat << 'EOF' > /home/user/fec_lib/fec.h
#include <stdint.h>
#include <stddef.h>
uint32_t compute_fec(const uint8_t* buffer, size_t length);
EOF

    cat << 'EOF' > /home/user/fec_lib/Makefile
libfec.so: fec.c
	gcc -shared -o libfec.so fec.c
EOF

    mkdir -p /home/user/video_processor/src
    cat << 'EOF' > /home/user/video_processor/Cargo.toml
[package]
name = "video_processor"
version = "0.1.0"
edition = "2021"

[dependencies]
reqwest = { version = "0.11", features = ["blocking", "json"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/video_processor/build.rs
fn main() {
    println!("cargo:rustc-link-lib=fec");
}
EOF

    cat << 'EOF' > /home/user/video_processor/src/main.rs
// Intentional slow/buggy implementation
use std::process::{Command, Stdio};
use std::io::Read;
use serde::Serialize;
use std::time::Duration;
use std::thread;

extern "C" {
    fn compute_fec(buffer: *const u8, length: usize) -> u32;
}

#[derive(Serialize)]
struct SingleSubmit {
    frame: usize,
    checksum: u32,
}

fn main() {
    let mut child = Command::new("ffmpeg")
        .args(&["-i", "/app/video.mp4", "-f", "image2pipe", "-vcodec", "rawvideo", "-pix_fmt", "rgb24", "-"])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("Failed to start ffmpeg");

    let mut stdout = child.stdout.take().unwrap();

    // Hardcoded dimensions assuming 640x360
    let frame_size = 640 * 360 * 3;
    let mut buffer = vec![0; frame_size];
    let mut frame_idx = 0;
    let client = reqwest::blocking::Client::new();

    while stdout.read_exact(&mut buffer).is_ok() {
        let checksum = unsafe { compute_fec(buffer.as_ptr(), buffer.len()) };
        let payload = SingleSubmit { frame: frame_idx, checksum };

        loop {
            let res = client.post("http://127.0.0.1:8080/submit").json(&payload).send().unwrap();
            if res.status().is_success() {
                break;
            }
            // Rate limited
            thread::sleep(Duration::from_millis(100));
        }
        frame_idx += 1;
    }
}
EOF

    cat << 'EOF' > /home/user/validator_service.py
from flask import Flask, request, jsonify
import time
import json

app = Flask(__name__)
received_frames = {}

last_submit_time = 0
last_batch_time = 0

@app.route('/submit', methods=['POST'])
def submit():
    global last_submit_time
    now = time.time()
    if now - last_submit_time < 0.05: # 20 req/sec limit
        return jsonify({"error": "Rate limit exceeded"}), 429
    last_submit_time = now

    data = request.json
    received_frames[data['frame']] = data['checksum']
    with open("/tmp/validator_results.json", "w") as f:
        json.dump(received_frames, f)
    return jsonify({"status": "ok"})

@app.route('/batch', methods=['POST'])
def batch():
    global last_batch_time
    now = time.time()
    if now - last_batch_time < 0.2: # 5 req/sec limit
        return jsonify({"error": "Rate limit exceeded"}), 429
    last_batch_time = now

    data = request.json
    for item in data.get('batches', []):
        received_frames[item['frame']] = item['checksum']
    with open("/tmp/validator_results.json", "w") as f:
        json.dump(received_frames, f)
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(port=8080)
EOF

    # Ensure the service runs when bash is started
    echo "python3 /home/user/validator_service.py > /dev/null 2>&1 &" >> /etc/bash.bashrc

    # Also create a wrapper for python3 tests to start the service first
    mv /usr/bin/python3 /usr/bin/python3.real
    cat << 'EOF' > /usr/bin/python3
#!/bin/bash
if ! pgrep -f "validator_service.py" > /dev/null; then
    /usr/bin/python3.real /home/user/validator_service.py > /dev/null 2>&1 &
    sleep 1
fi
exec /usr/bin/python3.real "$@"
EOF
    chmod +x /usr/bin/python3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
