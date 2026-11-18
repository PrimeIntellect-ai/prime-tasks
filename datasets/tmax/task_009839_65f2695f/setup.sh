#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y apt-transport-https ca-certificates gnupg
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential curl
    pip3 install pytest setuptools

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/target-api/src
    mkdir -p /home/user/api-emulator/src

    # Create target-api files
    cat << 'EOF' > /home/user/target-api/src/token.c
#include <Python.h>
static PyObject* verify_token(PyObject* self, PyObject* args) {
    return Py_BuildValue("s", "token_verified_securely");
}
static PyMethodDef AuthMethods[] = {
    {"verify_token", verify_token, METH_VARARGS, "Verify auth token."},
    {NULL, NULL, 0, NULL}
};
static struct PyModuleDef authmodule = {
    PyModuleDef_HEAD_INIT, "auth_ext", NULL, -1, AuthMethods
};
PyMODINIT_FUNC PyInit_auth_ext(void) {
    return PyModule_Create(&authmodule);
}
EOF

    cat << 'EOF' > /home/user/target-api/setup.py
from setuptools import setup, Extension
module1 = Extension('auth_ext', sources = ['src/auth_token.c'])
setup(name = 'TargetAPI', version = '1.0', ext_modules = [module1])
EOF

    cat << 'EOF' > /home/user/target-api/main.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import auth_ext

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        token_status = auth_ext.verify_token()
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(f"Status: {token_status}".encode())

if __name__ == '__main__':
    server = HTTPServer(('localhost', 8000), RequestHandler)
    server.serve_forever()
EOF

    # Create api-emulator files
    cat << 'EOF' > /home/user/api-emulator/Cargo.toml
[package]
name = "api-emulator"
version = "0.1.0"
edition = "2021"
[dependencies]
ureq = "2.6"
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/api-emulator/src/main.rs
use std::env;
use std::fs;
use std::io::Write;

struct Context {
    base_url: String,
    history: Vec<String>,
}

impl Context {
    fn record(&mut self, action: &str) {
        self.history.push(action.to_string());
    }
}

fn execute_script(script: &str, ctx: &mut Context) {
    let lines: Vec<&str> = script.lines().collect();
    let history_ref = &mut ctx.history;

    for line in lines {
        history_ref.push(format!("Executing: {}", line));
        let url = format!("{}/", ctx.base_url); // ERROR: cannot borrow `*ctx` immutably because it is also borrowed mutably
        if line.starts_with("GET") {
            let res = ureq::get(&url).call();
            if let Ok(r) = res {
                history_ref.push(format!("Response: {}", r.into_string().unwrap_or_default()));
            }
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 5 { return; }
    let script_path = &args[2];
    let base_url = &args[3];
    let out_path = &args[4];

    let script_content = fs::read_to_string(script_path).unwrap();
    let mut context = Context { base_url: base_url.to_string(), history: vec![] };

    execute_script(&script_content, &mut context);

    let json = serde_json::to_string(&context.history).unwrap();
    let mut file = fs::File::create(out_path).unwrap();
    file.write_all(json.as_bytes()).unwrap();
}
EOF

    # Create test script
    cat << 'EOF' > /home/user/test_script.dsl
GET /
EOF

    # Fix permissions and make Rust available for user
    echo 'export PATH="/root/.cargo/bin:${PATH}"' >> /home/user/.bashrc
    chmod -R 777 /home/user
    chmod -R 777 /root/.cargo || true
    chmod -R 777 /root/.rustup || true
