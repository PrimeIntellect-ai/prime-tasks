#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo netcat-openbsd curl
pip3 install pytest

mkdir -p /home/user/stack_restore/app/src

cat << 'EOF' > /home/user/stack_restore/backend_service.sh
#!/bin/bash
echo "Starting backend service container..."
sleep 4
echo "[INFO] Loading restored blocks..."
sleep 2
echo "[INFO] Listening for connections on port 8085"
# Keep port open using python to simulate the backend
python3 -c "import http.server; import socketserver; socketserver.TCPServer(('', 8085), http.server.SimpleHTTPRequestHandler).serve_forever()"
EOF
chmod +x /home/user/stack_restore/backend_service.sh

cat << 'EOF' > /home/user/stack_restore/start_all.sh
#!/bin/bash
cd /home/user/stack_restore
./backend_service.sh > backend.log 2>&1 &
BACKEND_PID=$!

# The bug is here: no wait loop
./app/target/release/restore_verifier

kill $BACKEND_PID
EOF
chmod +x /home/user/stack_restore/start_all.sh

cat << 'EOF' > /home/user/stack_restore/app/Cargo.toml
[package]
name = "restore_verifier"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /home/user/stack_restore/app/src/main.rs
use std::net::TcpStream;
use std::fs::File;
use std::io::Write;

fn main() {
    // Hardcoded port, needs to be changed to read from env var BACKEND_PORT
    let port = "9999"; 
    let address = format!("127.0.0.1:{}", port);

    match TcpStream::connect(&address) {
        Ok(_) => {
            let mut file = File::create("/home/user/restore_results.log").expect("Failed to create log");
            // Needs to write the exact string: RESTORE_SUCCESS: Verified data connection
            file.write_all(b"Connected").expect("Failed to write to log");
            println!("Successfully connected to backend.");
        }
        Err(e) => {
            panic!("Failed to connect to backend at {}: {}", address, e);
        }
    }
}
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
