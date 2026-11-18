#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git curl build-essential cargo rustc
pip3 install pytest

mkdir -p /home/user/db-exporter
cd /home/user/db-exporter
git init
git config user.name "Dev"
git config user.email "dev@example.com"

cat << 'EOF' > Cargo.toml
[package]
name = "db-exporter"
version = "0.1.0"
edition = "2021"
EOF

mkdir -p src
cat << 'EOF' > src/main.rs
use std::fs::File;
use std::io::Write;

fn query_data() -> Vec<String> {
    vec![
        "Hello, World!".to_string(),
        "こんにちは世界".to_string(),
        "Rustaceans 🦀".to_string()
    ]
}

fn serialize_string(s: &str, buf: &mut Vec<u8>) {
    let len = s.len();
    buf.extend_from_slice(&(len as u32).to_le_bytes());
    buf.extend_from_slice(s.as_bytes());
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() > 1 && args[1] == "export" {
        let data = query_data();
        let mut buf = Vec::new();
        buf.extend_from_slice(&(data.len() as u32).to_le_bytes());
        for s in data {
            serialize_string(&s, &mut buf);
        }
        let mut file = File::create("output.bin").unwrap();
        file.write_all(&buf).unwrap();
    }
}
EOF

git add .
git commit -m "Initial commit"

cargo run -- export
cp output.bin /home/user/expected.bin

for i in $(seq 2 200); do
  if [ $i -eq 137 ]; then
    sed -i 's/let len = s.len();/let len = s.chars().count();/' src/main.rs
  else
    echo "// comment $i" >> src/main.rs
  fi
  git commit -am "Commit $i"
done

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
