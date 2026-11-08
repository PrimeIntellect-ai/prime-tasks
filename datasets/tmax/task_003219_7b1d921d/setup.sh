#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo espeak ffmpeg
    pip3 install pytest hypothesis SpeechRecognition

    mkdir -p /app
    espeak -w /app/architect_notes.wav "The validation rules are simple. Reject any path that contains two consecutive dots representing parent directories. Also reject any path that starts with a forward slash. Finally, reject any path that includes the exact directory name dot git anywhere in the path structure."

    mkdir -p /home/user/project/fast_path/src
    cat << 'EOF' > /home/user/project/fast_path/Cargo.toml
[package]
name = "fast_path"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/project/fast_path/src/main.rs
fn main() {
    let s = get_string();
    println!("{}", s);
}

fn get_string() -> &'static str {
    let s = String::from("hello");
    &s
}
EOF

    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    echo '{"paths": ["src/main.py", "../secret.txt"]}' > /app/corpora/evil/1.json
    echo '{"paths": ["/etc/passwd"]}' > /app/corpora/evil/2.json
    echo '{"paths": ["src/.git/config"]}' > /app/corpora/evil/3.json

    echo '{"paths": ["src/main.py", "docs/index.md"]}' > /app/corpora/clean/1.json
    echo '{"paths": ["README.md"]}' > /app/corpora/clean/2.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
