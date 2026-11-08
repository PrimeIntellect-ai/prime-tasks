#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc ffmpeg fonts-dejavu-core
    pip3 install pytest requests

    mkdir -p /home/user/api_scanner/src /home/user/api_scanner/tests
    cd /home/user/api_scanner

    cat << 'EOF' > Cargo.toml
[package]
name = "fast_fuzzer"
version = "0.1.0"
edition = "2021"

[lib]
name = "fast_fuzzer"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.19.0", features = ["extension-module"] }
EOF

    cat << 'EOF' > src/lib.rs
use pyo3::prelude::*;

// BUG: Inefficiently taking ownership of String instead of borrowing &str.
// Causes massive allocation overhead.
#[pyfunction]
fn process_payload(payload: String) -> PyResult<usize> {
    let mut score = 0;
    for c in payload.chars() {
        score += c as usize;
    }
    Ok(score)
}

#[pymodule]
fn fast_fuzzer(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(process_payload, m)?)?;
    Ok(())
}
EOF

    cat << 'EOF' > scanner.py
import fast_fuzzer
import requests
import ssl

def run_scan(payloads):
    # Setup mock SSL context that CI relies on
    ctx = ssl.create_default_context()
    results = []
    for p in payloads:
        results.append(fast_fuzzer.process_payload(p))
    return results
EOF

    touch requirements.txt
    touch tests/test_integration.py

    mkdir -p /app
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=6 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='CRASH_PAYLOAD\: 1a2b3c':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,1,2)', drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='CRASH_PAYLOAD\: 4d5e6f':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,2,3)', drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='CRASH_PAYLOAD\: 7g8h9i':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,3,4)', drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='CRASH_PAYLOAD\: 0j1k2l':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,4,5)', drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='CRASH_PAYLOAD\: 3m4n5o':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,5,6)'" -c:v libx264 -t 6 /app/fuzz_session.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
