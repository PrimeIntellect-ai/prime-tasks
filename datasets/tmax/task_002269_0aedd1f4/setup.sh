#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl gcc build-essential tesseract-ocr imagemagick
pip3 install pytest

# Install Rust minimally
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
export PATH="/root/.cargo/bin:$PATH"

mkdir -p /app
# Generate image using ImageMagick
convert -size 800x100 xc:white -font DejaVu-Sans -pointsize 18 -fill black -draw "text 10,50 'FATAL ERROR: Stack overflow detected at frame 0x48f9a2. Context: MAX_ITERATIONS=1048576'" /app/crash_trace.png

mkdir -p /home/user/project/src
mkdir -p /home/user/project/clib

cat << 'EOF' > /home/user/project/Cargo.toml
[package]
name = "matrix_solver"
version = "0.1.0"
edition = "2021"

[dependencies]
libc = "0.2"

[build-dependencies]
cc = "1.0"
EOF

cat << 'EOF' > /home/user/project/build.rs
fn main() {
    cc::Build::new()
        .file("clib/math_core.c")
        .compile("math_core");
}
EOF

cat << 'EOF' > /home/user/project/src/main.rs
extern "C" {
    fn compute_matrix_power(n: libc::c_longlong);
}

fn main() {
    unsafe {
        compute_matrix_power(1048576);
    }
}
EOF

cat << 'EOF' > /home/user/project/src/logger.rs
#[no_mangle]
pub extern "C" fn log_message() {
    println!("Logging from Rust!");
}
EOF

cat << 'EOF' > /home/user/project/clib/math_core.c
#include <stdio.h>

extern void log_message();

void compute_matrix_power(long long n) {
    log_message();
    long long a = 1, b = 1, c = 1, d = 0;
    long long ra = 1, rb = 0, rc = 0, rd = 1;
    for (long long i = 0; i < n; i++) {
        long long ta = (ra * a + rb * c) % 9973;
        long long tb = (ra * b + rb * d) % 9973;
        long long tc = (rc * a + rd * c) % 9973;
        long long td = (rc * b + rd * d) % 9973;
        ra = ta; rb = tb; rc = tc; rd = td;
    }
    printf("Result: [%lld, %lld, %lld, %lld]\n", ra, rb, rc, rd);
}
EOF

cat << 'EOF' > /app/ref.c
#include <stdio.h>

void compute_matrix_power(long long n) {
    long long a = 1, b = 1, c = 1, d = 0;
    long long ra = 1, rb = 0, rc = 0, rd = 1;
    for (long long i = 0; i < n; i++) {
        long long ta = (ra * a + rb * c) % 9973;
        long long tb = (ra * b + rb * d) % 9973;
        long long tc = (rc * a + rd * c) % 9973;
        long long td = (rc * b + rd * d) % 9973;
        ra = ta; rb = tb; rc = tc; rd = td;
    }
    printf("Result: [%lld, %lld, %lld, %lld]\n", ra, rb, rc, rd);
}

int main() {
    compute_matrix_power(1048576);
    return 0;
}
EOF

gcc -O0 /app/ref.c -o /app/reference_c_impl

cat << 'EOF' > /app/verify.py
import time
import subprocess
import sys

def run_cmd(cmd):
    start = time.time()
    res = subprocess.run(cmd, capture_output=True, text=True)
    duration = time.time() - start
    return res, duration

ref_res, ref_dur = run_cmd(["/app/reference_c_impl"])
agent_res, agent_dur = run_cmd(["/home/user/project/target/release/matrix_solver"])

if agent_res.returncode != 0:
    sys.exit(1)

if "Result: [7582, 3811, 3811, 3771]" not in agent_res.stdout:
    sys.exit(1)

if ref_dur / agent_dur < 20.0:
    sys.exit(1)

sys.exit(0)
EOF

chmod +x /app/verify.py

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
