#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential cargo
pip3 install pytest maturin setuptools

mkdir -p /home/user/project/c_ext
mkdir -p /home/user/project/rust_ext/src
mkdir -p /home/user/project/tests

# 1. Create data.json
cat << 'EOF' > /home/user/project/data.json
[
  {"headers": {"X-Sec-Token": "SEC-1234567890"}},
  {"headers": {"X-Sec-Token": "SEC-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-LONG-TOKEN-THAT-CAUSES-BUFFER-OVERFLOW-IF-NOT-CAREFUL-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"}}
]
EOF

# 2. Create C extension setup.py
cat << 'EOF' > /home/user/project/c_ext/setup.py
from setuptools import setup, Extension
module = Extension('fast_sec', sources=['fast_sec.c'])
setup(name='fast_sec', version='1.0', ext_modules=[module])
EOF

# 3. Create C extension with a buffer overflow bug
cat << 'EOF' > /home/user/project/c_ext/fast_sec.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <string.h>

static PyObject* parse_token(PyObject* self, PyObject* args) {
    const char* input_str;
    // BUG: Buffer is too small, Py2 version assumed max 32 chars, Py3 inputs are larger.
    char buffer[64]; 

    if (!PyArg_ParseTuple(args, "s", &input_str)) {
        return NULL;
    }

    // Memory safety issue here: strcpy without length check
    strcpy(buffer, input_str);

    // Simulate "parsing" by stripping "SEC-" prefix if present
    char* result = buffer;
    if (strncmp(buffer, "SEC-", 4) == 0) {
        result += 4;
    }

    return PyUnicode_FromString(result);
}

static PyMethodDef FastSecMethods[] = {
    {"parse_token", parse_token, METH_VARARGS, "Parse security token."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastsecmodule = {
    PyModuleDef_HEAD_INIT, "fast_sec", NULL, -1, FastSecMethods
};

PyMODINIT_FUNC PyInit_fast_sec(void) {
    return PyModule_Create(&fastsecmodule);
}
EOF

# 4. Create Rust Cargo.toml
cat << 'EOF' > /home/user/project/rust_ext/Cargo.toml
[package]
name = "rust_sec"
version = "0.1.0"
edition = "2021"

[lib]
name = "rust_sec"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.19.0", features = ["extension-module"] }
EOF

# 5. Create Rust extension with borrow checker bug
cat << 'EOF' > /home/user/project/rust_ext/src/lib.rs
use pyo3::prelude::*;

// BUG: Returning a reference to a local variable (borrow checker error)
#[pyfunction]
fn parse_token(token: String) -> PyResult<&'static str> {
    let mut parsed = token.clone();
    if parsed.starts_with("SEC-") {
        parsed = parsed.split_off(4);
    }
    // Intentional borrow checker failure.
    // The correct fix is to change return type to PyResult<String> and return Ok(parsed)
    let s: &str = &parsed;
    let s_static: &'static str = unsafe { std::mem::transmute(s) }; // Simulate lifetime confusion attempt
    Ok(s_static)
}

#[pymodule]
fn rust_sec(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(parse_token, m)?)?;
    Ok(())
}
EOF

# 6. Create empty test file for agent
touch /home/user/project/tests/test_parser.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
