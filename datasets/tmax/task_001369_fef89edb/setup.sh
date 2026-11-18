#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/cleaner/src
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/cleaner/Cargo.toml
[package]
name = "cleaner"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.3.0"
unicode-normalization = "0.1.22"
EOF

    cat << 'EOF' > /home/user/cleaner/src/main.rs
fn main() {
    println!("Write your code here!");
}
EOF

    python3 -c '
import os
os.makedirs("/home/user/data", exist_ok=True)
with open("/home/user/data/reviews.csv", "wb") as f:
    f.write(b"id,review_2023_01,review_2023_02,review_2023_03\n")
    f.write(b"p1,cafe\xcc\x81,,good\n")
    f.write(b"p2,\xff\xfehello,Great,\n")
    f.write(b"p3,,\xe3\x81\x82\xe3\x82\x8a\xe3\x81\x8c\xe3\x81\xa8\xe3\x81\x86,\xd9\x85\xd9\x85\xd8\xaa\xd8\xa7\xd8\xb2\n")
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/cleaner /home/user/data
    chmod -R 777 /home/user
