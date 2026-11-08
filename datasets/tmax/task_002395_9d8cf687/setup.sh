#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo rustc
    pip3 install pytest

    mkdir -p /home/user/web_eval/parser/src

    # Create Cargo.toml
    cat << 'EOF' > /home/user/web_eval/parser/Cargo.toml
[package]
name = "parser"
version = "0.1.0"
edition = "2021"

[lib]
name = "parser"
crate-type = ["staticlib"]
EOF

    # Create buggy Rust lib.rs
    cat << 'EOF' > /home/user/web_eval/parser/src/lib.rs
use std::ffi::CStr;
use std::os::raw::c_char;

struct Evaluator<'a> {
    tokens: Vec<&'a str>,
}

impl<'a> Evaluator<'a> {
    fn new(expr: &'a str) -> Self {
        // BUG: clean_expr is a local variable, creating a dangling reference.
        let clean_expr = expr.trim().to_string();
        let tokens: Vec<&str> = clean_expr.split_whitespace().collect();
        Evaluator { tokens } 
    }

    fn eval(&self) -> f64 {
        let mut stack: Vec<f64> = Vec::new();
        for t in &self.tokens {
            if let Ok(n) = t.parse::<f64>() {
                stack.push(n);
            } else {
                let b = stack.pop().unwrap_or(0.0);
                let a = stack.pop().unwrap_or(0.0);
                match *t {
                    "+" => stack.push(a + b),
                    "-" => stack.push(a - b),
                    "*" => stack.push(a * b),
                    "/" => stack.push(a / b),
                    _ => {}
                }
            }
        }
        stack.pop().unwrap_or(0.0)
    }
}

#[no_mangle]
pub extern "C" fn evaluate_rpn(c_expr: *const c_char) -> f64 {
    if c_expr.is_null() { return 0.0; }
    let c_str = unsafe { CStr::from_ptr(c_expr) };
    if let Ok(expr) = c_str.to_str() {
        let evaluator = Evaluator::new(expr);
        evaluator.eval()
    } else {
        0.0
    }
}
EOF

    # Create buggy C server
    cat << 'EOF' > /home/user/web_eval/server.c
#include <stdio.h>

// BUG: Wrong function name declared
extern double evaluate_expression(const char* expr);

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    // BUG: Wrong function name called
    double res = evaluate_expression(argv[1]);
    printf("%f\n", res);
    return 0;
}
EOF

    # Create buggy Makefile
    cat << 'EOF' > /home/user/web_eval/Makefile
server: server.c
	gcc server.c -o server
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
