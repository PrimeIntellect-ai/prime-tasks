#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc coreutils binutils
    pip3 install pytest

    # Create the Rust binary
    mkdir -p /app/src
    cat << 'EOF' > /app/src/main.rs
use std::env;
fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 { std::process::exit(1); }
    let ref_seq = args[1].as_bytes();
    let primer = args[2].as_bytes();
    if primer.len() > ref_seq.len() {
        println!("0");
        return;
    }
    let mut max_score = i32::MIN;
    for i in 0..=(ref_seq.len() - primer.len()) {
        let mut score = 0;
        for j in 0..primer.len() {
            let r = ref_seq[i+j];
            let p = primer[j];
            score += match (r, p) {
                (b'A', b'A') | (b'T', b'T') => 5,
                (b'C', b'C') | (b'G', b'G') => 4,
                (b'A', b'T') | (b'T', b'A') => -2,
                (b'C', b'G') | (b'G', b'C') => -3,
                _ => -1,
            };
        }
        if score > max_score { max_score = score; }
    }
    println!("{}", max_score);
}
EOF
    cd /app/src && rustc -O main.rs -o /app/primer_match
    strip /app/primer_match
    rm -rf /app/src

    # Create input data
    mkdir -p /home/user
    head -c 2000000 /dev/urandom | base64 | tr -dc 'ACGT' | head -c 50000 > /home/user/reference.txt
    for i in $(seq 1 5000); do
        head -c 1000 /dev/urandom | base64 | tr -dc 'ACGT' | head -c 20 >> /home/user/primers.txt
        echo "" >> /home/user/primers.txt
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
