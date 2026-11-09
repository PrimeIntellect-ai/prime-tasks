#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core rustc
pip3 install pytest

mkdir -p /app

# Generate the PII list image
convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"GANDALF\nVOLDEMORT\nSAURON\nSKYWALKER" /app/pii_list.png

# Create the oracle implementation
cat << 'EOF' > /app/oracle.rs
use std::env;
use std::fs::File;
use std::io::{self, BufRead, BufReader};

fn url_decode(input: &str) -> String {
    let mut out = String::new();
    let mut chars = input.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '%' {
            let mut hex = String::new();
            if let Some(h1) = chars.next() { hex.push(h1); }
            if let Some(h2) = chars.next() { hex.push(h2); }
            if let Ok(byte) = u8::from_str_radix(&hex, 16) {
                out.push(byte as char);
            }
        } else if c == '+' {
            out.push(' ');
        } else {
            out.push(c);
        }
    }
    out
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let dict_file = File::open(&args[1]).unwrap();
    let words: Vec<String> = BufReader::new(dict_file).lines().map(|l| l.unwrap()).collect();

    let stdin = io::stdin();
    let mut history = vec![0, 0, 0];
    let mut count = 0;

    for line in stdin.lock().lines() {
        let line = line.unwrap();
        let mut decoded = url_decode(&line);
        let mut replacements_this_line = 0;

        for word in &words {
            let mut start = 0;
            while let Some(idx) = decoded[start..].find(word) {
                decoded.replace_range(start + idx..start + idx + word.len(), "[REDACTED]");
                replacements_this_line += 1;
                start = start + idx + 10;
            }
        }

        history[count % 3] = replacements_this_line;
        count += 1;

        let active_history = if count < 3 { count } else { 3 };
        let sum: usize = (0..active_history).map(|i| history[(count - 1 - i) % 3]).sum();

        println!("{}\t{}", decoded, sum);
    }
}
EOF

# Compile the oracle
rustc /app/oracle.rs -o /app/oracle_cleaner
chmod +x /app/oracle_cleaner

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
