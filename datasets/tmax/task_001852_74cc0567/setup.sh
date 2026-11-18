#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo build-essential
pip3 install pytest

mkdir -p /home/user/expr_ffi/src
mkdir -p /app/corpora/evil
mkdir -p /app/corpora/clean

cat << 'EOF' > /home/user/expr_ffi/Cargo.toml
[package]
name = "expr_ffi"
version = "0.1.0"
edition = "2021"

[dependencies]

[build-dependencies]
cc = "1.0"
EOF

cat << 'EOF' > /home/user/expr_ffi/build.rs
fn main() {
    // Intentionally broken, missing compile step
    println!("cargo:rerun-if-changed=src/libexpr.c");
}
EOF

cat << 'EOF' > /home/user/expr_ffi/src/libexpr.c
#include <stdio.h>
int evaluate(const char* expr) {
    return 0;
}
EOF

cat << 'EOF' > /home/user/expr_ffi/src/main.rs
mod sanitizer;
use std::env;
use std::fs;
use std::process;

extern "C" {
    fn evaluate(expr: *const std::os::raw::c_char) -> std::os::raw::c_int;
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        process::exit(1);
    }
    let content = fs::read_to_string(&args[1]).unwrap();
    if !sanitizer::is_safe_expression(&content) {
        process::exit(1);
    }
    process::exit(0);
}
EOF

cat << 'EOF' > /home/user/expr_ffi/src/sanitizer.rs
pub fn is_safe_expression(expr: &str) -> bool {
    // TODO: Implement sanitizer
    true
}
EOF

echo "((((((((((((((((1))))))))))))))))" > /app/corpora/evil/evil_1.txt
echo "1 / 0" > /app/corpora/evil/evil_2.txt
echo "1 ++ 2" > /app/corpora/evil/evil_3.txt

echo "1 + 2 * (3 - 4)" > /app/corpora/clean/clean_1.txt
echo "10 / 2" > /app/corpora/clean/clean_2.txt

cat << 'EOF' > /app/reference_oracle
#!/bin/bash
echo "0"
EOF
chmod +x /app/reference_oracle

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
