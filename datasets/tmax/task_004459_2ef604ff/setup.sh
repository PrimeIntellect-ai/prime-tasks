#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind cargo
    pip3 install pytest

    mkdir -p /home/user/telemetry/src

    cat << 'EOF' > /home/user/telemetry/Cargo.toml
[package]
name = "telemetry"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/telemetry/src/lib.rs
pub fn process_data(id: i32, value: f64) {
    println!("Processed: {} -> {}", id, value);
}
EOF

    cat << 'EOF' > /home/user/raw_data.log
[START]
ID: 1
VAL: 10.5
[END]
[START]
ID: 2
[START]
ID: 3
VAL: 15.0
[END]
ID: 4
VAL: 20.0
[END]
[START]
ID: 5
VAL: 25.5
EOF

    cat << 'EOF' > /home/user/runner.c
#include <stdio.h>
#include <stdlib.h>

extern void process_data(int id, double value);

int main() {
    FILE *fp = fopen("/home/user/clean.csv", "r");
    if (!fp) return 1;

    int id;
    double val;
    while (fscanf(fp, "%d,%lf", &id, &val) == 2) {
        process_data(id, val);
    }

    fclose(fp);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
