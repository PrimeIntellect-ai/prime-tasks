#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo make
pip3 install pytest

mkdir -p /app/log-alerter/src
mkdir -p /home/user/alerts

cat << 'EOF' > /app/log-alerter/Cargo.toml
[package]
name = "log-alerter"
version = "0.1.0"
edition = "2021"

[dependencies]
regex = "1.10.2"
lettre = "0.11"
EOF

cat << 'EOF' > /app/log-alerter/src/main.rs
use regex::Regex;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;

fn main() {
    let log_file = "/app/large_access.log";
    let file = File::open(log_file).unwrap();
    let reader = BufReader::new(file);

    let mut count = 0;
    for line in reader.lines() {
        let line = line.unwrap();
        // PERTURBATION: Regex compiled in loop
        let re = Regex::new("CRITICAL_ERROR").unwrap();
        if re.is_match(&line) {
            count += 1;
        }
    }

    let alert_dir = std::env::var("ALERT_DIR").unwrap_or_else(|_| ".".to_string());
    let mut out = File::create(format!("{}/summary.log", alert_dir)).unwrap();
    writeln!(out, "Found {} critical errors", count).unwrap();

    // Send mock email
    if let Ok(mut stream) = TcpStream::connect("127.0.0.1:2525") {
        let email = format!("HELO localhost\r\nMAIL FROM:<alert@system.local>\r\nRCPT TO:<admin@system.local>\r\nDATA\r\nSubject: Alert\r\n\r\nFound {} errors\r\n.\r\nQUIT\r\n", count);
        let _ = stream.write_all(email.as_bytes());
    }
}
EOF

cat << 'EOF' > /app/log-alerter/Makefile
all:
	cargo build
EOF

# Create a dummy large log file with some CRITICAL_ERRORs
python3 -c '
import random
with open("/app/large_access.log", "w") as f:
    for i in range(100000):
        if random.random() < 0.01:
            f.write(f"192.168.1.{i%255} - - [10/Oct/2023:13:55:36 -0700] \"GET /api/v1/data HTTP/1.1\" 500 1234 \"-\" \"curl/7.68.0\" CRITICAL_ERROR\n")
        else:
            f.write(f"192.168.1.{i%255} - - [10/Oct/2023:13:55:36 -0700] \"GET /index.html HTTP/1.1\" 200 4321 \"-\" \"Mozilla/5.0\"\n")
'

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/monitor.sh
#!/bin/bash
# Mock cron execution wrapper
cd /app/log-alerter
./target/debug/log-alerter
EOF
chmod +x /home/user/monitor.sh

chmod -R 777 /app
chmod -R 777 /home/user
