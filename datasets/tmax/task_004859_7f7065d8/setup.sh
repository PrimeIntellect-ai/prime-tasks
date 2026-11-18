#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make cargo rustc
    pip3 install pytest

    mkdir -p /home/user/pipeline/c_src
    mkdir -p /home/user/pipeline/rust_src/src

    cat << 'EOF' > /home/user/pipeline/c_src/filter.c
int is_valid_event(int code) {
    return code >= 100 && code <= 300;
}
EOF

    cat << 'EOF' > /home/user/pipeline/c_src/Makefile
all: libfilter.so

filter.o: filter.c
	gcc -c filter.c -o filter.o

libfilter.so: filter.o
	gcc filter.o -o libfilter.so
EOF

    cat << 'EOF' > /home/user/pipeline/rust_src/Cargo.toml
[package]
name = "parser"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

[build-dependencies]
cc = "1.0"
EOF

    cat << 'EOF' > /home/user/pipeline/rust_src/build.rs
fn main() {
    println!("cargo:rustc-link-search=native=/home/user/pipeline/c_src");
    println!("cargo:rustc-link-lib=dylib=filter");
}
EOF

    cat << 'EOF' > /home/user/pipeline/rust_src/src/main.rs
use serde::Serialize;
use std::env;
use std::fs;

extern "C" {
    fn is_valid_event(code: i32) -> i32;
}

#[derive(Serialize)]
struct Event<'a> {
    code: i32,
    data: &'a str,
}

enum State {
    Waiting,
    InEvent(i32),
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: parser <input> <output>");
        std::process::exit(1);
    }
    let input = fs::read_to_string(&args[1]).unwrap();

    let mut events = Vec::new();
    let mut state = State::Waiting;
    let mut current_data = String::new();

    for line in input.lines() {
        let parts: Vec<&str> = line.splitn(2, ' ').collect();
        match state {
            State::Waiting => {
                if parts[0] == "BEGIN" && parts.len() == 2 {
                    if let Ok(code) = parts[1].parse::<i32>() {
                        state = State::InEvent(code);
                    }
                }
            }
            State::InEvent(code) => {
                if parts[0] == "DATA" && parts.len() == 2 {
                    current_data = parts[1].to_string();
                } else if parts[0] == "END" {
                    unsafe {
                        if is_valid_event(code) == 1 {
                            events.push(Event {
                                code,
                                data: &current_data,
                            });
                        }
                    }
                    state = State::Waiting;
                    current_data.clear();
                }
            }
        }
    }

    let out_json = serde_json::to_string(&events).unwrap();
    fs::write(&args[2], out_json).unwrap();
}
EOF

    cat << 'EOF' > /home/user/input.log
BEGIN 200
DATA login_success
END
BEGIN 400
DATA bad_request
END
BEGIN 150
DATA processing
END
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
