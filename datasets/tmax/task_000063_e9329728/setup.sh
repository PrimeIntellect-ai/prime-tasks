#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils cargo rustc
    pip3 install pytest

    mkdir -p /home/user/processor_service/src
    cd /home/user/processor_service

    cat << 'EOF' > tracker.c
#include <stddef.h>
void track_allocation(size_t size) {
    // dummy implementation
}
EOF

    gcc -c tracker.c -o tracker.o
    ar rcs libtracker.a tracker.o

    cat << 'EOF' > Cargo.toml
[package]
name = "processor_service"
version = "0.1.0"
edition = "2021"
build = "build.rs"

[dependencies]
EOF

    cat << 'EOF' > build.rs
fn main() {
    println!("cargo:rustc-link-search=native=.");
    // MISSING: link directive for static lib
}
EOF

    cat << 'EOF' > src/main.rs
use std::env;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Write};

extern "C" {
    fn track_allocation(size: usize);
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <logfile>", args[0]);
        std::process::exit(1);
    }

    let file = File::open(&args[1]).unwrap();
    let reader = BufReader::new(file);

    for line in reader.lines() {
        let l = line.unwrap();
        unsafe { track_allocation(l.len()); }

        if l == "REQ_METHOD:POST PATH:/api/v1/data ID:7781-FAIL-99" {
            // Trigger leak simulation
            let mut dummy_heap: Vec<u8> = vec![0; 1024];
            let leak_str = b"SOME_GARBAGE_DATA_LEAKED_SESSION_ID:SESS88392011X_END_GARBAGE";
            dummy_heap[500..500+leak_str.len()].copy_from_slice(leak_str);

            let mut dump = File::create("heap.raw").unwrap();
            dump.write_all(&dummy_heap).unwrap();

            panic!("Memory limit exceeded!");
        }
    }
}
EOF

    cd /home/user
    for i in $(seq 1 200); do echo "REQ_METHOD:GET PATH:/api/v1/health ID:100$i" >> traffic.log; done
    echo "REQ_METHOD:POST PATH:/api/v1/data ID:7781-FAIL-99" >> traffic.log
    for i in $(seq 201 499); do echo "REQ_METHOD:GET PATH:/api/v1/health ID:100$i" >> traffic.log; done

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
