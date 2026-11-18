#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cargo
    pip3 install pytest maturin hypothesis

    mkdir -p /home/user/expr-eval/src
    mkdir -p /home/user/expr-eval/tests

    cat << 'EOF' > /home/user/expr-eval/Cargo.toml
[package]
name = "rpn-eval"
version = "0.1.0"
edition = "2021"

[lib]
name = "rpn_eval"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.19.0", features = ["extension-module"] }
EOF

    cat << 'EOF' > /home/user/expr-eval/pyproject.toml
[build-system]
requires = ["maturin>=1.0,<2.0"]
build-backend = "maturin"

[project]
name = "rpn_eval"
requires-python = ">=3.7"
classifiers = [
    "Programming Language :: Rust",
    "Programming Language :: Python :: Implementation :: CPython",
    "Programming Language :: Python :: Implementation :: PyPy",
]
EOF

    cat << 'EOF' > /home/user/expr-eval/src/lib.rs
use pyo3::prelude::*;

#[pyfunction]
fn evaluate_rpn(expression: &str) -> PyResult<f64> {
    let mut stack: Vec<f64> = Vec::new();

    let mut tokens: Vec<&str> = Vec::new();
    for token in expression.split_whitespace() {
        let t = token.to_string();
        tokens.push(&t); // Borrow checker error: t dropped here while still borrowed
    }

    for token in tokens {
        if let Ok(num) = token.parse::<f64>() {
            stack.push(num);
        } else {
            let b = stack.pop().unwrap_or(0.0);
            let a = stack.pop().unwrap_or(0.0);
            let res = match *token {
                "+" => a + b,
                "-" => b - a, // BUG: Should be a - b
                "*" => a * b,
                "/" => b / a, // BUG: Should be a / b
                _ => 0.0,
            };
            stack.push(res);
        }
    }
    Ok(stack.pop().unwrap_or(0.0))
}

#[pymodule]
fn rpn_eval(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(evaluate_rpn, m)?)?;
    Ok(())
}
EOF

    cat << 'EOF' > /home/user/expr-eval/tests/test_eval.py
import pytest
from hypothesis import given
import hypothesis.strategies as st
from rpn_eval import evaluate_rpn

def test_simple_addition():
    assert evaluate_rpn("2 3 +") == 5.0

@given(st.lists(st.floats(min_value=-100, max_value=100), min_size=2, max_size=2))
def test_subtraction_property(lst):
    a, b = lst
    expr = f"{a} {b} -"
    assert abs(evaluate_rpn(expr) - (a - b)) < 1e-5

@given(st.lists(st.floats(min_value=1, max_value=100), min_size=2, max_size=2))
def test_division_property(lst):
    a, b = lst
    expr = f"{a} {b} /"
    assert abs(evaluate_rpn(expr) - (a / b)) < 1e-5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
