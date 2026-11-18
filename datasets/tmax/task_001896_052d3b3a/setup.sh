#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        cargo \
        tesseract-ocr \
        imagemagick \
        build-essential

    pip3 install pytest

    # Create the app directory
    mkdir -p /app

    # Generate the params image
    # Note: imagemagick policy might block some operations, but simple generation usually works.
    convert -size 400x200 xc:white -fill black -pointsize 24 -annotate +20+40 "ALGORITHM SPEC V2\nMULTIPLIER=16807\nMODULO=2147483647" /app/params.png

    # Create oracle source code
    cat << 'EOF' > /tmp/oracle.rs
use std::io::{self, Read};

const MULTIPLIER: u64 = 16807;
const MODULO: u64 = 2147483647;

struct RingBuffer {
    data: Vec<u8>,
    capacity: usize,
    head: usize,
}

impl RingBuffer {
    fn new(capacity: usize) -> Self {
        RingBuffer {
            data: Vec::new(),
            capacity,
            head: 0,
        }
    }
    fn push(&mut self, val: u8) {
        if self.data.len() < self.capacity {
            self.data.push(val);
        } else {
            self.data[self.head] = val;
            self.head = (self.head + 1) % self.capacity;
        }
    }
    fn get_items(&self) -> Vec<&u8> {
        let mut items = Vec::new();
        if self.data.len() < self.capacity {
            for i in 0..self.data.len() {
                items.push(&self.data[i]);
            }
        } else {
            for i in self.head..self.capacity {
                items.push(&self.data[i]);
            }
            for i in 0..self.head {
                items.push(&self.data[i]);
            }
        }
        items
    }
}

struct RollingHash {
    rb: RingBuffer,
    total_hash: u64,
}

impl RollingHash {
    fn new() -> Self {
        RollingHash {
            rb: RingBuffer::new(4),
            total_hash: 0,
        }
    }
    fn update(&mut self, val: u8) {
        self.rb.push(val);
        let mut window_hash: u64 = 0;
        let items = self.rb.get_items();
        for &wb in items {
            window_hash = (window_hash.wrapping_mul(MULTIPLIER).wrapping_add(wb as u64)) % MODULO;
        }
        self.total_hash = self.total_hash.wrapping_add(window_hash);
    }
}

fn main() {
    let mut buffer = Vec::new();
    io::stdin().read_to_end(&mut buffer).unwrap();

    let mut rh = RollingHash::new();
    for &b in &buffer {
        rh.update(b);
    }
    println!("{:016x}", rh.total_hash);
}
EOF

    # Compile oracle
    rustc -O /tmp/oracle.rs -o /app/oracle
    rm /tmp/oracle.rs

    # Create user
    useradd -m -s /bin/bash user || true

    # Create agent project
    mkdir -p /home/user/hash_util/src
    cat << 'EOF' > /home/user/hash_util/Cargo.toml
[package]
name = "hash_util"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/hash_util/src/main.rs
use std::io::{self, Read};

// TODO: Extract these from /app/params.png
const MULTIPLIER: u64 = 0;
const MODULO: u64 = 0;

struct RingBuffer {
    data: Vec<u8>,
    capacity: usize,
    head: usize,
}

impl RingBuffer {
    fn new(capacity: usize) -> Self {
        RingBuffer {
            data: Vec::new(),
            capacity,
            head: 0,
        }
    }
    fn push(&mut self, val: u8) {
        if self.data.len() < self.capacity {
            self.data.push(val);
        } else {
            self.data[self.head] = val;
            self.head = (self.head + 1) % self.capacity;
        }
    }

    // Intentional lifetime error: returning references with unconstrained lifetime 'a
    fn get_items<'a>(&self) -> Vec<&'a u8> {
        let mut items = Vec::new();
        if self.data.len() < self.capacity {
            for i in 0..self.data.len() {
                items.push(&self.data[i]);
            }
        } else {
            for i in self.head..self.capacity {
                items.push(&self.data[i]);
            }
            for i in 0..self.head {
                items.push(&self.data[i]);
            }
        }
        items
    }
}

struct RollingHash {
    rb: RingBuffer,
    total_hash: u64,
}

impl RollingHash {
    fn new() -> Self {
        RollingHash {
            rb: RingBuffer::new(4),
            total_hash: 0,
        }
    }
    fn update(&mut self, val: u8) {
        self.rb.push(val);
        let mut window_hash: u64 = 0;
        let items = self.rb.get_items();
        for &wb in items {
            window_hash = (window_hash.wrapping_mul(MULTIPLIER).wrapping_add(wb as u64)) % MODULO;
        }
        self.total_hash = self.total_hash.wrapping_add(window_hash);
    }
}

fn main() {
    let mut buffer = Vec::new();
    io::stdin().read_to_end(&mut buffer).unwrap();

    let mut rh = RollingHash::new();
    for &b in &buffer {
        rh.update(b);
    }
    println!("{:016x}", rh.total_hash);
}
EOF

    # Set permissions
    chmod -R 777 /home/user
    chmod 755 /app/oracle
    chmod 644 /app/params.png
