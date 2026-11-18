#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect cargo rustc
pip3 install pytest

useradd -m -s /bin/bash user || true

# Setup required before the agent starts
mkdir -p /home/user/bin
mkdir -p /home/user/analyzer/src

# Create the dummy cap_cli.sh
cat << 'EOF' > /home/user/cap_cli.sh
#!/bin/bash
read -s -p "Enter capacity planner password: " pass
echo ""
if [ "$pass" = "cap123" ]; then
    echo "host1,45,1024"
    echo "host2,60,2048"
    echo "host3,80,4096"
else
    echo "Auth failed"
    exit 1
fi
EOF
chmod +x /home/user/cap_cli.sh

# Create the initial dummy symlink
touch /home/user/bin/analyzer_v1
chmod +x /home/user/bin/analyzer_v1
ln -s /home/user/bin/analyzer_v1 /home/user/bin/analyzer

# Create the Rust project files
cat << 'EOF' > /home/user/analyzer/Cargo.toml
[package]
name = "analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /home/user/analyzer/src/main.rs
use std::io::{self, BufRead};
use std::fs::File;
use std::io::Write;

fn main() {
    let stdin = io::stdin();
    let mut total_mem = 0;

    for line in stdin.lock().lines() {
        let line = line.unwrap();
        if line.trim().is_empty() { continue; }
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() >= 3 {
            if let Ok(mem) = parts[2].parse::<i32>() {
                total_mem += mem;
            }
        }
    }

    // BUG: Hardcoded path instead of using REPORT_PATH
    let mut file = File::create("/tmp/wrong_path.txt").unwrap();
    writeln!(file, "Total Mem: {}", total_mem).unwrap();
}
EOF

chmod -R 777 /home/user
