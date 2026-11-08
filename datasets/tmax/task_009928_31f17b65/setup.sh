#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils rustc cargo
pip3 install pytest

mkdir -p /home/user/weight_service/src
mkdir -p /home/user/weight_service/.cargo
cd /home/user/weight_service

# Create the C source code (hidden from the agent)
cat << 'EOF' > calc.c
double intermediate = 0.0; // The shared state causing the race condition
double compute_weights(double x, double y) {
    intermediate = x - y;
    // Small sleep to encourage race conditions during high load
    for(volatile int i=0; i<1000; i++); 
    return 1.0 / intermediate;
}
EOF

# Compile the C library
gcc -shared -fPIC -O0 -o libcalc.so calc.c
rm calc.c

# Create Cargo.toml
cat << 'EOF' > Cargo.toml
[package]
name = "weight_service"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

# Create Rust main.rs
cat << 'EOF' > src/main.rs
use std::thread;
use std::sync::Arc;

#[link(name = "calc", kind = "dylib")]
extern "C" {
    fn compute_weights(x: f64, y: f64) -> f64;
}

fn main() {
    let mut handles = vec![];

    for i in 0..100 {
        let handle = thread::spawn(move || {
            let x = 10.0 + (i as f64);
            let y = 5.0 + (i as f64);
            unsafe {
                let res = compute_weights(x, y);
                if res.is_infinite() || res.is_nan() {
                    println!("Numerical instability detected: {}", res);
                }
            }
        });
        handles.push(handle);
    }

    for handle in handles {
        handle.join().unwrap();
    }
}
EOF

# Configure dynamic linker
echo "build.rustflags = [\"-C\", \"link-arg=-Wl,-rpath=/home/user/weight_service\"]" > .cargo/config.toml

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
