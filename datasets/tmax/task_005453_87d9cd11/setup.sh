#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo build-essential curl
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/ref.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int match_pattern(const char* url, const char* pattern) {
    if (strstr(url, "/api/") != NULL) return 1;
    return 0;
}

int main(int argc, char** argv) {
    if (argc < 3) return 0;

    FILE* f_bc = fopen(argv[1], "r");
    if(!f_bc) return 0;
    FILE* f_urls = fopen(argv[2], "r");
    if(!f_urls) return 0;

    char bc_line[256];
    char* patterns[100];
    int p_count = 0;
    while (fgets(bc_line, sizeof(bc_line), f_bc)) {
        patterns[p_count++] = strdup(bc_line);
    }
    fclose(f_bc);

    char url_line[256];
    int match_count = 0;
    while (fgets(url_line, sizeof(url_line), f_urls)) {
        for (int i=0; i<p_count; i++) {
            if (match_pattern(url_line, patterns[i])) {
                match_count++;
                break;
            }
        }
    }
    fclose(f_urls);
    printf("Matches: %d\n", match_count);
    return 0;
}
EOF
    gcc -O3 -o /app/ref_router_vm /app/ref.c
    strip /app/ref_router_vm
    rm /app/ref.c

    mkdir -p /home/user/router_vm/c_src
    mkdir -p /home/user/router_vm/src

    cat << 'EOF' > /home/user/router_vm/Cargo.toml
[package]
name = "router_vm"
version = "0.1.0"
edition = "2021"

[dependencies]
libc = "0.2"
EOF

    cat << 'EOF' > /home/user/router_vm/build.rs
fn main() {
    // Missing C compilation logic
    println!("cargo:rustc-link-lib=matcher");
}
EOF

    cat << 'EOF' > /home/user/router_vm/c_src/matcher.c
#include <string.h>
int match_pattern(const char* url, const char* pattern) {
    if (strstr(url, "/api/") != NULL) return 1;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/router_vm/src/main.rs
use std::env;
use std::fs;
use std::ffi::CString;

extern "C" {
    fn match_pattern(url: *const libc::c_char, pattern: *const libc::c_char) -> libc::c_int;
}

fn parse_bytecode(bc: &str) -> Vec<String> {
    bc.lines().map(|s| s.to_string()).collect()
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 { return; }

    let bytecode_str = fs::read_to_string(&args[1]).unwrap();
    let urls_str = fs::read_to_string(&args[2]).unwrap();

    let mut match_count = 0;

    for url in urls_str.lines() {
        // BUG: Parsing bytecode inside the hot loop
        let instructions = parse_bytecode(&bytecode_str);

        let c_url = CString::new(url).unwrap();
        for inst in &instructions {
            let c_pattern = CString::new(inst.as_str()).unwrap();
            let matched = unsafe { match_pattern(c_url.as_ptr(), c_pattern.as_ptr()) };
            if matched == 1 {
                match_count += 1;
                break;
            }
        }
    }
    println!("Matches: {}", match_count);
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
