#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest python-Levenshtein

    mkdir -p /app
    mkdir -p /home/user/decoder/src

    # Create the transmission.wav file
    python3 -c "
import wave, base64
with wave.open('/app/transmission.wav', 'wb') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(44100)
    w.writeframes(b'\x00\x00' * 100)
with open('/app/transmission.wav', 'ab') as f:
    payload = b'CRITICAL_PAYLOAD_INITIATED_0x8F2A_OVERRIDE_ACTIVE'
    f.write(b'MARKER' + base64.b64encode(payload))
"

    # Create Cargo.toml with dependency conflicts / bad versions
    cat << 'EOF' > /home/user/decoder/Cargo.toml
[package]
name = "decoder"
version = "0.1.0"
edition = "2021"

[dependencies]
base64 = "99.0.0"
serde = "=1.0.100"
serde_json = "=1.0.50"
EOF

    # Create main.rs with deliberate bugs
    cat << 'EOF' > /home/user/decoder/src/main.rs
use std::env;
use std::fs;
use base64::{engine::general_purpose::URL_SAFE, Engine as _};

fn main() {
    let key = env::var("DECODER_KEY").unwrap_or_default();
    if key != "7734" {
        panic!("Missing or invalid DECODER_KEY environment configuration");
    }

    let data = fs::read("/app/transmission.wav").expect("Unable to read file");
    let content = String::from_utf8_lossy(&data);

    if let Some(idx) = content.find("MARKER") {
        let b64_str = &content[idx + 6..];
        // BUG: Using URL_SAFE instead of STANDARD
        let decoded = URL_SAFE.decode(b64_str.trim()).expect("Failed to decode base64");
        let result = String::from_utf8(decoded).expect("Invalid UTF-8");
        println!("Decoded: {}", result);
        fs::write("/home/user/extracted_payload.txt", result).expect("Failed to write output");
    } else {
        panic!("Marker not found in audio file");
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
