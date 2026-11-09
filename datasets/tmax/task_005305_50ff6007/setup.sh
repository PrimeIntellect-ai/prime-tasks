#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_pipeline/cpp_src
    mkdir -p /home/user/data_pipeline/src

    cat << 'EOF' > /home/user/data_pipeline/Cargo.toml
[package]
name = "data_pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]

[build-dependencies]
cc = "1.0"
EOF

    cat << 'EOF' > /home/user/data_pipeline/build.rs
fn main() {
    cc::Build::new()
        .file("cpp_src/processor.cpp")
        .compile("processor");
}
EOF

    cat << 'EOF' > /home/user/data_pipeline/cpp_src/processor.h
#pragma once

extern "C" {
    double process_data(const double* data, int len);
}
EOF

    cat << 'EOF' > /home/user/data_pipeline/cpp_src/processor.cpp
#include "processor.h"
#include <iostream>

extern "C" double process_data(const double* data, int len) {
    double sum = 0;
    for (int i = 0; i <= len; i++) {
        sum += data[i];
    }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/data_pipeline/src/main.rs
use std::env;

extern "C" {
    fn process_data(data: *const f64, len: i32) -> f64;
}

fn compute(values: &[f64]) -> f64 {
    unsafe {
        process_data(values.as_ptr(), values.len() as i32)
    }
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let nums: Vec<f64> = args.iter().filter_map(|s| s.parse().ok()).collect();

    if nums.is_empty() {
        println!("Result: 0");
        return;
    }

    let result = compute(&nums);
    println!("Result: {}", result);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compute() {
        let data = vec![1.0, 2.0, 3.0, 4.0, 5.0];
        let result = compute(&data);
        assert_eq!(result, 15.0);
    }
}
EOF

    chmod -R 777 /home/user
