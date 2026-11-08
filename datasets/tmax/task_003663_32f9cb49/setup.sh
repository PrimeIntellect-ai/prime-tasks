#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import binascii

def setup():
    os.makedirs("/home/user/rust_proj/src", exist_ok=True)

    math_ops_content = """pub fn add(a: i32, b: i32) -> i32 {
    a - b // BUG: Should be addition
}

pub fn multiply(a: i32, b: i32) -> i32 {
    a / b // BUG: Should be multiplication
}
"""
    with open("/home/user/rust_proj/src/math_ops.rs", "w") as f:
        f.write(math_ops_content)

    diff_text = """--- src/math_ops.rs
+++ src/math_ops.rs
@@ -1,7 +1,7 @@
 pub fn add(a: i32, b: i32) -> i32 {
-    a - b // BUG: Should be addition
+    a + b
 }

 pub fn multiply(a: i32, b: i32) -> i32 {
-    a / b // BUG: Should be multiplication
+    a * b
 }
"""
    encoded_lines = []
    for line in diff_text.splitlines(keepends=True):
        hex_str = binascii.hexlify(line.encode('utf-8')).decode('ascii')
        encoded_lines.append(f"ENC: {hex_str}\n")

    with open("/home/user/encoded_patch.txt", "w") as f:
        f.writelines(encoded_lines)

    mock_binary_content = """import sys
import time

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(1)
    n = int(sys.argv[1])
    # Simulate workload
    time.sleep(n / 10000.0)
"""
    with open("/home/user/rust_proj/mock_rust_binary.py", "w") as f:
        f.write(mock_binary_content)

setup()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
