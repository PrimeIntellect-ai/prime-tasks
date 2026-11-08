#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored/math-ingest-v1.2.0/bin
    mkdir -p /opt/oracle
    mkdir -p /home/user/data

    # Create ingest.wal
    cat << 'EOF' > /home/user/data/ingest.wal
[1623423400] (1) 10
[1623423401] (2) 20
[1623423402] (3) 30
[1623423403] (4) 40
[1623423404] (5) 50
[1623423423] (12) 0
[1623423424] (13) INVALID
EOF
    # Add more valid lines to reach ~50
    for i in $(seq 14 60); do
        echo "[16234234$i] ($i) $i" >> /home/user/data/ingest.wal
    done

    # Create Rust binary source
    cat << 'EOF' > /tmp/checksum_calc.rs
use std::env;
use std::fs::File;
use std::io::{self, BufRead};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 { return; }
    let file = File::open(&args[1]).unwrap();
    for line in io::BufReader::new(file).lines() {
        if let Ok(l) = line {
            let parts: Vec<&str> = l.split_whitespace().collect();
            if parts.len() >= 3 {
                if let Ok(val) = parts[2].parse::<i32>() {
                    if val <= 0 {
                        panic!("Math error on {}", val);
                    }
                    let res = (val * 17) % 256 + 42;
                    println!("{}", res);
                } else {
                    // simulate unwrap panic on invalid
                    parts[2].parse::<i32>().unwrap();
                }
            }
        }
    }
}
EOF
    rustc /tmp/checksum_calc.rs -o /app/vendored/math-ingest-v1.2.0/bin/checksum_calc
    rm /tmp/checksum_calc.rs

    # Create oracle
    cat << 'EOF' > /opt/oracle/reference_checksum_calc
#!/bin/bash
val=$1
res=$(( (val * 17) % 256 + 42 ))
echo $res
EOF
    chmod +x /opt/oracle/reference_checksum_calc

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
