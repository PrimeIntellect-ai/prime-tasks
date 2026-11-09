#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo
pip3 install pytest Pillow

mkdir -p /app
python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'f(x) = (1 - cos(x)) / x^2', fill=(0,0,0))
img.save('/app/formula.png')
"

mkdir -p /home/user/engine/src
cat << 'EOF' > /home/user/engine/Cargo.toml
[package]
name = "engine"
version = "0.1.0"
edition = "2021"
EOF

cat << 'EOF' > /home/user/engine/src/main.rs
use std::env;

fn compute(x: f64) -> f64 {
    // UNSTABLE IMPLEMENTATION
    (1.0 - x.cos()) / (x * x)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: engine <x>");
        std::process::exit(1);
    }
    let x: f64 = args[1].parse().expect("Invalid float");
    println!("{:.16}", compute(x));
}
EOF

python3 -c "
import struct
# The value x = 1.2345e-8
x_val = 1.2345e-08
marker = b'FAIL_X_VAL='
# pack as little-endian 64-bit float
packed_float = struct.pack('<d', x_val)

with open('/home/user/crash.bin', 'wb') as f:
    # some garbage bytes
    f.write(b'\x00\x01\xFF\xFA' * 10)
    f.write(marker)
    f.write(packed_float)
    # more garbage
    f.write(b'\x44\x33\x22\x11' * 10)
"

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
