#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc time curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    # Create directories
    mkdir -p /home/user/data /home/user/math_ops /home/user/verifier/src /home/user/artifacts

    # Create datasets
    seq 1 2 100 > /home/user/data/setA.txt
    seq 1 3 100 > /home/user/data/setB.txt

    # Create C program
    cat << 'EOF' > /home/user/math_ops/main.c
#include <stdio.h>
#include <stdlib.h>

int cmp(const void *a, const void *b) {
    return (*(int*)a - *(int*)b);
}

void process(const char* f1, const char* f2) {
    int A[1000], B[1000];
    int nA = 0, nB = 0;
    FILE *fp1 = fopen(f1, "r");
    FILE *fp2 = fopen(f2, "r");
    while (fscanf(fp1, "%d", &A[nA]) == 1) nA++;
    while (fscanf(fp2, "%d", &B[nB]) == 1) nB++;
    fclose(fp1); fclose(fp2);

    qsort(A, nA, sizeof(int), cmp);
    qsort(B, nB, sizeof(int), cmp);

    int i = 0, j = 0;
    while (i < nA && j < nB) {
        if (A[i] < B[j]) { printf("%d\n", A[i]); i++; }
        else if (A[i] > B[j]) { printf("%d\n", B[j]); j++; }
        else { i++; j++; }
    }
    while (i < nA) { printf("%d\n", A[i]); i++; }
    while (j < nB) { printf("%d\n", B[j]); j++; }
}

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    process(argv[1], argv[2]);
    return 0;
}
EOF

    # Create Rust project
    cat << 'EOF' > /home/user/verifier/Cargo.toml
[package]
name = "verifier"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /home/user/verifier/src/main.rs
use std::env;
use std::fs;

// Bug: Returning a reference to a locally created String (or strictly, moving a String and taking a ref).
fn read_lines(file_path: &str) -> Vec<String> {
    let content = fs::read_to_string(file_path).unwrap();
    content.lines().map(|s| s.to_string()).collect()
}

fn get_diff<'a>(a: Vec<String>, b: Vec<String>) -> Vec<&'a String> {
    let mut diff = Vec::new();
    // Borrow checker bug: iterating over owned Vecs but trying to return references to their contents
    // without returning the Vecs or taking references as arguments.
    for val in &a {
        if !b.contains(val) {
            diff.push(val); // ERROR
        }
    }
    for val in &b {
        if !a.contains(val) {
            diff.push(val); // ERROR
        }
    }
    diff
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let a_lines = read_lines(&args[1]);
    let b_lines = read_lines(&args[2]);

    // The fix requires modifying get_diff to take references: get_diff(&a_lines, &b_lines)
    // or return owned Strings.
    let diff = get_diff(a_lines, b_lines);

    let mut parsed: Vec<i32> = diff.iter().map(|s| s.parse().unwrap()).collect();
    parsed.sort();
    for num in parsed {
        println!("{}", num);
    }
}
EOF

    # Ensure cargo is available to the user
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
