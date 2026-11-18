#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git curl
    pip3 install pytest

    # Install Rust globally
    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    export PATH="/usr/local/cargo/bin:$PATH"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /usr/local/cargo /usr/local/rustup

    # Create directories and data
    mkdir -p "/home/user/incoming_data"
    echo "[NODE: [NODE: leaf_alpha]]" > "/home/user/incoming_data/data one.txt"
    echo "[NODE: leaf_beta]" > "/home/user/incoming_data/data two.txt"

    # Setup Git repository
    mkdir -p "/home/user/data_pipeline"
    cd "/home/user/data_pipeline"
    git init
    git config user.email "junior.dev@example.com"
    git config user.name "Junior Dev"

    # First commit: working code with hardcoded token
    cat << 'EOF' > Cargo.toml
[package]
name = "data_parser"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    mkdir src
    cat << 'EOF' > src/main.rs
use std::env;
use std::fs;

const API_TOKEN: &str = "sk-9942b-secret-token";

fn parse_node(data: &str) -> String {
    if data.starts_with("[NODE: ") && data.ends_with("]") {
        let inner = &data[7..data.len()-1];
        parse_node(inner)
    } else {
        data.to_string()
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        return;
    }
    let content = fs::read_to_string(&args[1]).unwrap();
    let parsed = parse_node(content.trim());
    println!("PROCESSED: {} WITH {}", parsed, API_TOKEN);
}
EOF

    git add Cargo.toml src/main.rs
    git commit -m "Initial commit with working parser"

    # Second commit: introduce bugs (recursion, missing dependency, token removal)
    cat << 'EOF' > src/main.rs
use std::env;
use std::fs;
use regex::Regex;

fn parse_node(data: &str) -> String {
    if data.starts_with("[NODE: ") && data.ends_with("]") {
        parse_node(data)
    } else {
        data.to_string()
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        return;
    }
    let token = fs::read_to_string("/home/user/secret.txt").unwrap();
    let content = fs::read_to_string(&args[1]).unwrap();

    let re = Regex::new(r"^\s*|\s*$").unwrap();
    let cleaned = re.replace_all(&content, "");

    let parsed = parse_node(&cleaned);

    use std::io::Write;
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("/home/user/output.log")
        .unwrap();
    writeln!(file, "PROCESSED: {} WITH {}", parsed, token.trim()).unwrap();
}
EOF

    git add src/main.rs
    git commit -m "Hotfix: use secret file, clean input, refactor parser"

    # Create buggy shell script
    cat << 'EOF' > process_all.sh
#!/bin/bash
for f in $(ls /home/user/incoming_data/); do
    /home/user/data_pipeline/target/debug/data_parser "/home/user/incoming_data/$f"
done
EOF
    chmod +x process_all.sh

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    echo 'export PATH="/usr/local/cargo/bin:$PATH"' >> /home/user/.bashrc
    chmod -R 777 /home/user
