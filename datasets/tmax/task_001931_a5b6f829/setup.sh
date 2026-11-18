#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        cargo \
        rustc \
        git \
        unzip \
        strace \
        imagemagick \
        zip \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app
    cd /app

    # Generate clue image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 36 -fill black -draw "text 20,60 'b1s3ct_s3cr3t!'" /app/clue.png

    # Generate corpus
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    printf "\x01\x08data.txt" > /app/corpus/clean/file1.bin
    printf "\x01\x09image.png" > /app/corpus/clean/file2.bin

    printf "\x02\x10../../etc/passwd" > /app/corpus/evil/file1.bin
    printf "\x02\x0b../root.txt" > /app/corpus/evil/file2.bin

    cd /app
    zip -P "b1s3ct_s3cr3t!" -r corpus.zip corpus
    rm -rf corpus

    # Create Git repository
    mkdir -p /app/parser_repo
    cd /app/parser_repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    cargo init --bin .

    # Commit 0
    cat << 'EOF' > src/main.rs
use std::env;
use std::fs::File;
use std::io::Read;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 { return; }
    let mut f = File::open(&args[1]).unwrap();
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).unwrap();
    if buf.len() < 2 { return; }
    let typ = buf[0];
    let len = buf[1] as usize;
    if buf.len() < 2 + len { return; }
    let fname = String::from_utf8_lossy(&buf[2..2+len]);
    if typ == 0x02 || fname.contains("../") {
        println!("Unsafe!");
        return;
    }
    println!("Safe!");
}
EOF
    git add src/main.rs Cargo.toml
    git commit -m "Initial commit"

    # Commits 1-99
    for i in $(seq 1 99); do
        echo "// Dummy $i" >> src/main.rs
        git commit -am "Dummy $i"
    done

    # Commits 100-105 (Syntax error)
    for i in $(seq 100 105); do
        echo "syntax error $i" >> src/main.rs
        git commit -am "Syntax error $i"
    done

    # Commits 106-141
    git checkout HEAD~6 src/main.rs
    for i in $(seq 106 141); do
        echo "// Dummy $i" >> src/main.rs
        git commit -am "Dummy $i"
    done

    # Commit 142 (Regression)
    cat << 'EOF' > src/main.rs
use std::env;
use std::fs::File;
use std::io::Read;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 { return; }
    let mut f = File::open(&args[1]).unwrap();
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).unwrap();
    if buf.len() < 2 { return; }
    let _typ = buf[0];
    let len = buf[1] as usize;
    if buf.len() < 2 + len { return; }
    let fname = String::from_utf8_lossy(&buf[2..2+len]);
    // Regression: removed check
    let _ = File::open(fname.as_ref());
    println!("Parsed!");
}
EOF
    git commit -am "Refactor parser"

    # Commits 143-200
    for i in $(seq 143 200); do
        echo "// Dummy $i" >> src/main.rs
        git commit -am "Dummy $i"
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
