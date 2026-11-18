#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/encryptor.rs
use std::env;
use std::fs;

struct LCG {
    state: u64,
}

impl LCG {
    fn new(seed: u16) -> Self {
        LCG { state: seed as u64 }
    }

    fn next_byte(&mut self) -> u8 {
        // Parameters: A = 1103515245, C = 12345, M = 2^31
        self.state = (1103515245 * self.state + 12345) % 2147483648;
        (self.state & 0xFF) as u8
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 4 {
        eprintln!("Usage: {} <seed> <input> <output>", args[0]);
        return;
    }

    let seed: u16 = args[1].parse().expect("Seed must be a 16-bit integer");
    let input = fs::read(&args[2]).expect("Failed to read input");

    let mut lcg = LCG::new(seed);
    let mut output = Vec::with_capacity(input.len());

    for byte in input {
        output.push(byte ^ lcg.next_byte());
    }

    fs::write(&args[3], output).expect("Failed to write output");
}
EOF

    cat << 'EOF' > /home/user/logs/plaintext.txt
[SECURE_LOG_V1]
2023-10-10 10:00:01 [INFO] System started
2023-10-10 10:05:23 [ALERT] MALWARE_SIGNATURE_MATCH detected from IP: 10.0.0.42 port: 4444
2023-10-10 10:06:00 [WARN] High CPU usage
2023-10-10 10:15:11 [ALERT] MALWARE_SIGNATURE_MATCH detected from IP: 192.168.1.100 port: 8080
2023-10-10 10:15:15 [INFO] User admin logged in
2023-10-10 10:20:05 [ALERT] MALWARE_SIGNATURE_MATCH detected from IP: 10.0.0.42 port: 4445
2023-10-10 10:25:00 [ALERT] BRUTE_FORCE_ATTACK detected from IP: 172.16.0.5 port: 22
EOF

    cd /home/user
    rustc encryptor.rs -o encryptor
    ./encryptor 42133 /home/user/logs/plaintext.txt /home/user/logs/encrypted_log.bin

    rm /home/user/logs/plaintext.txt
    rm /home/user/encryptor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
