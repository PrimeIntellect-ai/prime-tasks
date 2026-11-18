#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the parser project
    mkdir -p /home/user/parser/src

    cat << 'EOF' > /home/user/parser/Cargo.toml
[package]
name = "parser"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/parser/src/main.rs
use std::io::{Read, BufReader};
use std::fs::File;
use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <file>", args[0]);
        std::process::exit(1);
    }
    let file = File::open(&args[1]).unwrap();
    let mut reader = BufReader::new(file);

    let mut out = Vec::new();
    loop {
        let mut len_buf = [0u8; 1];
        if reader.read_exact(&mut len_buf).is_err() {
            break;
        }
        let len = len_buf[0] as usize;

        // BUG: Off-by-one boundary allocation
        let mut buf = vec![0u8; len + 1];
        reader.read_exact(&mut buf[..len]).unwrap();

        // Validation
        assert_eq!(buf.len(), len, "Buffer length must exactly match payload length!");

        let s = String::from_utf8_lossy(&buf[..len]);
        out.push(s.into_owned());
    }
    println!("{}", out.join(","));
}
EOF

    # Create the emitter daemon
    cat << 'EOF' > /home/user/metrics_emitter.py
import time
import os

f = open('/tmp/metrics.dat', 'wb')
f.write(b'\x04test\x05hello\x06urgent')
f.flush()
os.remove('/tmp/metrics.dat')

while True:
    time.sleep(10)
EOF

    chmod +x /home/user/metrics_emitter.py

    # Start the daemon when the container is executed
    cat << 'EOF' > /.singularity.d/env/99-daemon.sh
#!/bin/sh
if ! pgrep -f metrics_emitter.py > /dev/null; then
    nohup python3 /home/user/metrics_emitter.py > /dev/null 2>&1 &
    sleep 1
fi
EOF
    chmod +x /.singularity.d/env/99-daemon.sh

    chmod -R 777 /home/user
