#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-liberation \
        gcc \
        make \
        cargo \
        rustc \
        curl

    pip3 install pytest

    # Generate server config image
    mkdir -p /app
    convert -size 400x200 xc:white -fill black -pointsize 20 -annotate +10+30 "PORT=7331\nAPI_KEY=tesseract_secret_99\nMIGRATION_TARGET=v3" /app/server_config.png

    # Create C library files
    mkdir -p /home/user/clib
    cat << 'EOF' > /home/user/clib/math_ops.c
int add(int a, int b) {
    return a - b; // Bug to fix
}
EOF

    cat << 'EOF' > /home/user/clib/Makefile
libmathops.a: math_ops.o
ar rcs libmathops.a math_ops.o  # Bug: missing tab
math_ops.o: math_ops.c
	gcc -c math_ops.c
EOF

    # Create Rust project files
    mkdir -p /home/user/rust_svc/src
    cat << 'EOF' > /home/user/rust_svc/Cargo.toml
[package]
name = "rust_svc"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/rust_svc/build.rs
fn main() {
    println!("cargo:rustc-link-search=native=/home/user/clib");
    println!("cargo:rustc-link-lib=static=mathops");
}
EOF

    cat << 'EOF' > /home/user/rust_svc/src/main.rs
use std::env;

extern "C" {
    fn add(a: i32, b: i32) -> i32;
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        return;
    }
    let a: i32 = args[1].parse().unwrap();
    let b: i32 = args[2].parse().unwrap();

    // Bug: missing unsafe block
    let result = add(a, b);

    println!("{}", result);
}
EOF

    # Create schema files
    mkdir -p /home/user/schema
    echo "CREATE TABLE users (id INTEGER PRIMARY KEY);" > /home/user/schema/v1.sql
    echo "ALTER TABLE users ADD COLUMN name TEXT;" > /home/user/schema/v2.sql
    echo "ALTER TABLE users ADD COLUMN email TEXT;" > /home/user/schema/v3.sql

    # Setup user and permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
