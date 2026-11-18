#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl nginx rustc cargo
    pip3 install pytest

    mkdir -p /home/user/migration/rust_ext/src

    # Legacy Python 2 script
    cat << 'EOF' > /home/user/migration/legacy_app.py
import BaseHTTPServer
import urlparse

def reverse_string(s):
    return s[::-1]

class Handler(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse.urlparse(self.path)
        qs = urlparse.parse_qs(parsed.query)
        text = qs.get('text', [''])[0]

        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()

        reversed_text = reverse_string(text)
        self.wfile.write(reversed_text)

if __name__ == '__main__':
    server_address = ('127.0.0.1', 8000)
    httpd = BaseHTTPServer.HTTPServer(server_address, Handler)
    print "Starting server on port 8000..."
    httpd.serve_forever()
EOF

    # Rust Cargo.toml
    cat << 'EOF' > /home/user/migration/rust_ext/Cargo.toml
[package]
name = "rust_ext"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    # Buggy Rust code
    cat << 'EOF' > /home/user/migration/rust_ext/src/lib.rs
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn reverse_string(input: *const c_char) -> *const c_char {
    let c_str = unsafe { CStr::from_ptr(input) };
    let s = c_str.to_str().unwrap();
    let reversed: String = s.chars().rev().collect();
    let c_reversed = CString::new(reversed).unwrap();
    c_reversed.as_ptr() // Bug: returns dangling pointer
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/migration
    chmod -R 777 /home/user
