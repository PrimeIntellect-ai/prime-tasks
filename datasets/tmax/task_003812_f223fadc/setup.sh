#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate CA and server certificates
    openssl req -new -x509 -days 365 -nodes -out /home/user/ca.crt -keyout /home/user/ca.key -subj "/C=US/ST=State/L=City/O=Org/CN=MyRootCA"
    openssl req -new -nodes -out /home/user/server.csr -keyout /home/user/server.key -subj "/C=US/ST=State/L=City/O=Org/CN=127.0.0.1"

    # Use bash explicitly for process substitution
    bash -c 'openssl x509 -req -in /home/user/server.csr -CA /home/user/ca.crt -CAkey /home/user/ca.key -CAcreateserial -out /home/user/server.crt -days 365 -extfile <(echo "subjectAltName=IP:127.0.0.1")'

    # Create Python HTTPS server
    cat << 'EOF' > /home/user/server.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import ssl

class SecureHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/secure-endpoint':
            self.send_response(200)
            self.send_header('Set-Cookie', 'session_token=Th1sIsA_S3cr3t_T0k3n_8492; Secure; HttpOnly')
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Success')
        else:
            self.send_response(404)
            self.end_headers()

httpd = HTTPServer(('127.0.0.1', 8443), SecureHandler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile='/home/user/server.crt', keyfile='/home/user/server.key')
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
EOF

    # Ensure the server starts for agent shells and test runs
    echo "nohup python3 /home/user/server.py >/dev/null 2>&1 &" >> /etc/bash.bashrc

    # Hijack pytest to ensure the server is running during tests
    mv /usr/local/bin/pytest /usr/local/bin/pytest-real
    cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
nohup python3 /home/user/server.py >/dev/null 2>&1 &
sleep 1
/usr/local/bin/pytest-real "$@"
EOF
    chmod +x /usr/local/bin/pytest

    # Create Rust project
    mkdir -p /home/user/traffic-auditor/src

    cat << 'EOF' > /home/user/traffic-auditor/Cargo.toml
[package]
name = "traffic-auditor"
version = "0.1.0"
edition = "2021"

[dependencies]
reqwest = { version = "0.11", features = ["blocking", "rustls-tls"] }
sha2 = "0.10"
EOF

    cat << 'EOF' > /home/user/traffic-auditor/src/main.rs
use reqwest::blocking::Client;
use std::fs::File;
use std::io::Write;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // CWE-295: Accepting invalid certs
    let client = Client::builder()
        .danger_accept_invalid_certs(true)
        .build()?;

    let res = client.get("https://127.0.0.1:8443/secure-endpoint").send()?;

    // Developer left this unfinished
    let cookie_val = "TODO_EXTRACT_COOKIE"; 
    let hash = "TODO_HASH";

    // CWE-732: Incorrect file permissions (default permissions)
    let mut file = File::create("/home/user/cookie_hash.txt")?;
    file.write_all(hash.as_bytes())?;

    Ok(())
}
EOF

    chmod -R 777 /home/user
