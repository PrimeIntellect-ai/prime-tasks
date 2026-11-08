#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make ffmpeg cargo
    pip3 install pytest hypothesis numpy

    # Create the test video
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=2:size=320x240:rate=5 -c:v libx264 /app/test_video.mp4

    # Create directories
    mkdir -p /home/user/video_processor/c_src
    mkdir -p /home/user/video_processor/src
    mkdir -p /home/user/py_src

    # Create C source
    cat << 'EOF' > /home/user/video_processor/c_src/intensity.c
#include <stdint.h>

double calculate_intensity(const uint8_t* data, int length) {
    if (length <= 0) return 0.0;
    double sum = 0;
    for(int i = 0; i < length; i++) {
        sum += data[i];
    }
    return sum / length;
}
EOF

    # Create broken Makefile
    cat << 'EOF' > /home/user/video_processor/c_src/Makefile
libintensity.so: intensity.o
	gcc -o libintensity.so intensity.o

intensity.o: intensity.c
	gcc -c intensity.c
EOF

    # Create Rust main.rs
    cat << 'EOF' > /home/user/video_processor/src/main.rs
use std::env;
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::PathBuf;

// FFI bug: expects i32 for length, but C uses int (which is i32, but let's say the bug is rust declared it as f64)
extern "C" {
    fn calculate_intensity(data: *const u8, length: f64) -> f64; 
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        return;
    }
    let dir_path = &args[1];
    let out_path = &args[2];

    let mut entries: Vec<PathBuf> = fs::read_dir(dir_path)
        .unwrap()
        .map(|res| res.unwrap().path())
        .collect();
    entries.sort();

    let mut results = Vec::new();
    for path in entries {
        if path.is_file() {
            let mut file = File::open(&path).unwrap();
            let mut buffer = Vec::new();
            file.read_to_end(&mut buffer).unwrap();

            let val = unsafe {
                // Bug in casting here will be evident due to FFI mismatch
                calculate_intensity(buffer.as_ptr(), buffer.len() as f64)
            };
            results.push(val);
        }
    }

    let json = format!("{:?}", results);
    let mut out_file = File::create(out_path).unwrap();
    out_file.write_all(json.as_bytes()).unwrap();
}
EOF

    # Create Rust constants.rs with ISO-8859-1 encoding
    python3 -c 'open("/home/user/video_processor/src/constants.rs", "wb").write("pub const GREETING: &str = \"caf\xe9\";\n".encode("iso-8859-1"))'

    # Create Cargo.toml
    cat << 'EOF' > /home/user/video_processor/Cargo.toml
[package]
name = "video_processor"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    # Create build.rs
    cat << 'EOF' > /home/user/video_processor/build.rs
fn main() {
    println!("cargo:rustc-link-search=native=c_src");
    println!("cargo:rustc-link-lib=intensity");
}
EOF

    # Create Python processor
    cat << 'EOF' > /home/user/py_src/processor.py
def calculate_intensity(data: bytes) -> float:
    if not data:
        return 0.0
    return sum(data) / len(data)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
