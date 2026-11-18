#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/plugin_manager/src

    cat << 'EOF' > /home/user/plugin_manager/Cargo.toml
[package]
name = "plugin_manager"
version = "0.1.0"
edition = "2021"

[build-dependencies]
cc = "1.0"
EOF

    cat << 'EOF' > /home/user/plugin_manager/build.rs
fn main() {
    cc::Build::new()
        .file("src/libdeps.c")
        .compile("deps");
    println!("cargo:rerun-if-changed=src/libdeps.c");
}
EOF

    cat << 'EOF' > /home/user/plugin_manager/src/libdeps.c
#include <stdio.h>
#include <stdlib.h>

// Parses dependencies from file.
// Returns an array of integers where pairs (edges[i], edges[i+1]) represent a dependency.
// out_count will contain the number of *pairs*.
int* parse_deps(const char* filename, int* out_count) {
    FILE *f = fopen(filename, "r");
    if (!f) return NULL;

    int capacity = 2;
    int* edges = malloc(capacity * sizeof(int));
    int count = 0;
    int u, v;

    while(fscanf(f, "%d %d", &u, &v) == 2) {
        // BUG: checking if count >= capacity is insufficient because we add 2 elements!
        // It should be count + 1 >= capacity.
        if (count >= capacity) {
            capacity *= 2;
            edges = realloc(edges, capacity * sizeof(int));
        }
        edges[count++] = u;
        edges[count++] = v;
    }

    *out_count = count / 2;
    fclose(f);
    return edges;
}

void free_deps(int* edges) {
    free(edges);
}
EOF

    cat << 'EOF' > /home/user/plugin_manager/src/main.rs
use std::ffi::CString;
use std::os::raw::c_char;
use std::fs;

extern "C" {
    fn parse_deps(filename: *const c_char, out_count: *mut i32) -> *mut i32;
    fn free_deps(edges: *mut i32);
}

fn main() {
    let filename = CString::new("edges.txt").unwrap();
    let mut count: i32 = 0;

    let edges_ptr = unsafe { parse_deps(filename.as_ptr(), &mut count) };
    if edges_ptr.is_null() {
        panic!("Failed to parse deps");
    }

    let slice = unsafe { std::slice::from_raw_parts(edges_ptr, (count * 2) as usize) };

    // slice contains pairs of [A, B] where A depends on B.
    // TODO: Build your graph data structure here.
    // TODO: Implement topological sort with smallest-ID-first tie-breaking.
    // TODO: Write the space-separated result to /home/user/load_order.txt

    unsafe { free_deps(edges_ptr) };
}
EOF

    cat << 'EOF' > /home/user/plugin_manager/edges.txt
1 2
2 3
4 3
1 4
5 1
6 5
7 6
8 7
10 9
9 2
11 10
EOF

    chmod -R 777 /home/user
