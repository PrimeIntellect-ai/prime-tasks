#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        make \
        curl \
        build-essential

    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create directories
    mkdir -p /app/libmsgparse-1.2.0
    mkdir -p /home/user/msg_gateway/src
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create libmsgparse files
    cat << 'EOF' > /app/libmsgparse-1.2.0/msgparse.h
#ifndef MSGPARSE_H
#define MSGPARSE_H
#include <stddef.h>
void parse_msg(const unsigned char *data, size_t len);
#endif
EOF

    cat << 'EOF' > /app/libmsgparse-1.2.0/msgparse.c
#include "msgparse.h"
#include <string.h>
#include <stdlib.h>

void parse_msg(const unsigned char *data, size_t len) {
    if (len < 3) return;
    unsigned short payload_len = (data[1] << 8) | data[2];
    if (payload_len == 0) return;

    unsigned char *buffer = malloc(payload_len);
    if (!buffer) return;

    // Vulnerable memcpy: trusts payload_len, reads past data buffer if malformed
    memcpy(buffer, data + 3, payload_len);

    // Do something to prevent optimization
    volatile unsigned char sink = buffer[0];
    (void)sink;

    free(buffer);
}
EOF

    cat << 'EOF' > /app/libmsgparse-1.2.0/Makefile
CC = gcc
CFLAGS = -Wall -O2

all: libmsgparse.a

libmsgparse.a: msgparse.o
	ar rcs $@ $^

msgparse.o: msgparse.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o *.a *.so
EOF

    # Create Rust project files
    cat << 'EOF' > /home/user/msg_gateway/Cargo.toml
[package]
name = "msg_gateway"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/msg_gateway/build.rs
fn main() {
    println!("cargo:rustc-link-search=native=/app/libmsgparse-1.2.0");
    println!("cargo:rustc-link-lib=msgparse");
}
EOF

    cat << 'EOF' > /home/user/msg_gateway/src/main.rs
use std::env;
use std::fs;

#[link(name = "msgparse")]
extern "C" {
    fn parse_msg(data: *const u8, len: usize);
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        std::process::exit(1);
    }
    let filename = &args[1];
    let data = match fs::read(filename) {
        Ok(d) => d,
        Err(_) => std::process::exit(1),
    };

    // TODO: Implement validation logic here

    unsafe {
        parse_msg(data.as_ptr(), data.len());
    }
}
EOF

    # Generate corpora
    # Clean 1: Type 1, Len 2, Data: 0xAA, 0xBB
    printf "\x01\x00\x02\xAA\xBB" > /app/corpora/clean/msg1.bin
    # Clean 2: Type 2, Len 0
    printf "\x02\x00\x00" > /app/corpora/clean/msg2.bin

    # Evil 1: Type 1, Len 65535, Data: 0xAA (segfaults)
    printf "\x01\xFF\xFF\xAA" > /app/corpora/evil/evil1.bin
    # Evil 2: Type 2, Len 256, Data: 0xBB
    printf "\x02\x01\x00\xBB" > /app/corpora/evil/evil2.bin

    # Create user and fix permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/msg_gateway
    chmod -R 777 /home/user
    chmod -R 777 /app
