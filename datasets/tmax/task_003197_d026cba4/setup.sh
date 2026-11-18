#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo patch
    pip3 install pytest

    mkdir -p /home/user/rust_backend/src

    cat << 'EOF' > /home/user/rust_backend/Cargo.toml
[package]
name = "rust_backend"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/rust_backend/src/main.rs
use std::io::{Read, Write};
use std::net::TcpListener;

fn fib(n: u32) -> u32 {
    if n == 0 {
        1
    } else {
        fib(n - 1) + fib(n - 2)
    }
}

fn main() {
    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        let mut buffer = [0; 512];
        if let Err(_) = stream.read(&mut buffer) { continue; }
        let request = String::from_utf8_lossy(&buffer);
        let first_line = request.lines().next().unwrap_or("");
        let parts: Vec<&str> = first_line.split_whitespace().collect();
        if parts.len() >= 2 {
            let path = parts[1];
            if path.starts_with("/fib/") {
                let num_str = &path[5..];
                if let Ok(n) = num_str.parse::<u32>() {
                    let result = fib(n);
                    let response = format!("HTTP/1.1 200 OK\r\n\r\n{}", result);
                    let _ = stream.write(response.as_bytes());
                    continue;
                }
            }
        }
        let response = "HTTP/1.1 404 NOT FOUND\r\n\r\n";
        let _ = stream.write(response.as_bytes());
    }
}
EOF

    cat << 'EOF' > /home/user/rust_backend/fix_math.patch
--- src/main.rs
+++ src/main.rs
@@ -3,8 +3,8 @@
 use std::net::TcpListener;

 fn fib(n: u32) -> u32 {
-    if n == 0 {
-        1
+    if n <= 1 {
+        n
     } else {
         fib(n - 1) + fib(n - 2)
     }
EOF

    cat << 'EOF' > /home/user/proxy.py
import BaseHTTPServer
import urllib2

class ProxyHandler(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_GET(self):
        url = "http://127.0.0.1:8080" + self.path
        try:
            resp = urllib2.urlopen(url)
            body = resp.read()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)
        except Exception, e:
            print "Error:", e
            self.send_response(500)
            self.end_headers()

if __name__ == "__main__":
    server = BaseHTTPServer.HTTPServer(('127.0.0.1', 8000), ProxyHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/test_integration.py
import urllib.request
import sys

def main():
    try:
        resp = urllib.request.urlopen("http://127.0.0.1:8000/fib/10")
        res = resp.read().decode('utf-8').strip()
        with open('/home/user/test_results.txt', 'w') as f:
            f.write(res)
    except Exception as e:
        print(e)
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
