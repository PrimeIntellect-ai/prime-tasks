#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task dependencies
    apt-get install -y tesseract-ocr imagemagick fonts-dejavu-core gcc rustc cargo make

    mkdir -p /app
    mkdir -p /home/user/polyglot/compute_engine/src
    mkdir -p /home/user/polyglot/api

    # Generate algorithm specification image
    convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"ALGORITHM SPECIFICATION:\nTo compute the hash of input N:\n1. XOR N with 0x8BADF00D\n2. Multiply the result by 17\n3. Modulo the result by 1000003\n4. Output the final value." /app/algorithm_spec.png

    # Create Rust scaffolding
    cat << 'EOF' > /home/user/polyglot/compute_engine/Cargo.toml
[package]
name = "compute_engine"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/polyglot/compute_engine/src/main.rs
use std::env;

fn process(data: &mut String, val: &String) {
    data.push_str(val);
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 2 {
        std::process::exit(1);
    }
    let n_str = &args[1];
    let mut buffer = String::new();

    // Buggy borrowing
    let r1 = &buffer;
    process(&mut buffer, n_str);
    println!("Dummy {}", r1);
}
EOF

    # Create and compile oracle engine
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    long long N = atoll(argv[1]);
    long long res = ((N ^ 0x8BADF00D) * 17) % 1000003;
    printf("%lld\n", res);
    return 0;
}
EOF
    gcc -O3 /app/oracle.c -o /app/oracle_engine
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
