#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo rustc
    pip3 install pytest

    mkdir -p /app /home/user/auditor/legacy /home/user/auditor/patches /home/user/auditor/src

    # Create Cargo.toml
    cat << 'EOF' > /home/user/auditor/Cargo.toml
[package]
name = "side_channel_auditor"
version = "0.1.0"
edition = "2021"

[dependencies]
image = "0.24"
regex = "1"
EOF

    # Create Python legacy analyzer
    cat << 'EOF' > /home/user/auditor/legacy/analyzer.py
def extract_token(frame_paths):
    bits = ""
    for i in range(len(frame_paths)):
        # Read center pixel brightness logic
        pass
    # ... logic to convert bits to ascii string ...
EOF

    # Create patch file
    cat << 'EOF' > /home/user/auditor/patches/extractor.patch
--- src/main.rs
+++ src/main.rs
@@ -0,0 +1,10 @@
+fn main() {
+    // TODO: implement frame extraction and analysis
+}
EOF

    # Create src/main.rs
    cat << 'EOF' > /home/user/auditor/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    # Generate video
    cat << 'EOF' > /tmp/gen_video.py
import os
import subprocess

text = "SEC{0x4F}"
bits = "".join(f"{ord(c):08b}" for c in text)

with open("/tmp/frames.raw", "wb") as f:
    for bit in bits:
        color = 255 if bit == '1' else 0
        frame = bytes([color] * (100 * 100 * 3))
        f.write(frame)

subprocess.run(["ffmpeg", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "100x100", "-r", "10", "-i", "/tmp/frames.raw", "-c:v", "libx264", "-crf", "0", "-pix_fmt", "yuv444p", "/app/auth_feed.mp4"])
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py /tmp/frames.raw

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user /app
