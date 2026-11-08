#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential pkg-config cargo rustc
    pip3 install pytest

    # Create custom_lib directory structure
    mkdir -p /home/user/custom_lib/lib
    mkdir -p /home/user/custom_lib/include
    mkdir -p /home/user/custom_lib/pkgconfig

    # Create C source
    cat << 'EOF' > /home/user/custom_lib/mathops.c
int add_numbers(int a, int b) {
    return a + b;
}
EOF

    # Compile static library
    gcc -c /home/user/custom_lib/mathops.c -o /home/user/custom_lib/mathops.o
    ar rcs /home/user/custom_lib/lib/libmathops.a /home/user/custom_lib/mathops.o
    rm /home/user/custom_lib/mathops.c /home/user/custom_lib/mathops.o

    # Create header
    cat << 'EOF' > /home/user/custom_lib/include/mathops.h
#ifndef MATHOPS_H
#define MATHOPS_H
int add_numbers(int a, int b);
#endif
EOF

    # Create pkg-config file
    cat << 'EOF' > /home/user/custom_lib/pkgconfig/mathops.pc
prefix=/home/user/custom_lib
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: mathops
Description: Math operations library
Version: 1.0.0
Libs: -L${libdir} -lmathops
Cflags: -I${includedir}
EOF

    # Create Rust project
    mkdir -p /home/user/app/src
    cat << 'EOF' > /home/user/app/Cargo.toml
[package]
name = "app"
version = "0.1.0"
edition = "2021"

[build-dependencies]
pkg-config = "0.3"
EOF

    cat << 'EOF' > /home/user/app/build.rs
fn main() {
    pkg_config::Config::new()
        .statik(true)
        .probe("mathops")
        .expect("Failed to find mathops via pkg-config");
}
EOF

    cat << 'EOF' > /home/user/app/src/lib.rs
extern "C" {
    fn add_numbers(a: i32, b: i32) -> i32;
}

pub fn safe_add(a: i32, b: i32) -> i32 {
    unsafe { add_numbers(a, b) }
}

pub fn process_data(data: &mut Vec<i32>) {
    let val = data.first().unwrap();
    data.push(*val);
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/custom_lib /home/user/app
    chmod -R 777 /home/user
