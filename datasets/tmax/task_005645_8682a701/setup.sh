#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc rustc cargo
    pip3 install pytest

    mkdir -p /home/user/project_workspace/source_files
    mkdir -p /home/user/project_workspace/extractor/src

    # Create source files
    cat << 'EOF' > /home/user/project_workspace/source_files/main.c
#include "a.h"
#include "b.h"
int main() { return 0; }
EOF

    cat << 'EOF' > /home/user/project_workspace/source_files/a.c
#include "a.h"
#include "c.h"
EOF

    cat << 'EOF' > /home/user/project_workspace/source_files/b.c
#include "b.h"
EOF

    cat << 'EOF' > /home/user/project_workspace/source_files/c.c
#include "c.h"
EOF

    touch /home/user/project_workspace/source_files/a.h
    touch /home/user/project_workspace/source_files/b.h
    touch /home/user/project_workspace/source_files/c.h

    # Create Rust project
    cat << 'EOF' > /home/user/project_workspace/extractor/Cargo.toml
[package]
name = "extractor"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/project_workspace/extractor/src/main.rs
use std::fs;
use std::path::Path;

// INTENTIONAL BUG: returning a reference to a local variable
fn extract_includes<'a>(content: &'a str) -> Vec<&'a str> {
    let mut includes = Vec::new();
    for line in content.lines() {
        if line.starts_with("#include \"") {
            let start = 10;
            if let Some(end) = line[start..].find('"') {
                includes.push(&line[start..start + end]);
            }
        }
    }
    includes
}

fn process_file(path: &Path) -> Vec<String> {
    let content = fs::read_to_string(path).unwrap_or_default();
    // Borrow checker will fail here because content is dropped at the end of the function
    let refs = extract_includes(&content);
    refs.into_iter().map(|s| s.to_string()).collect()
}

fn main() {
    let dir = Path::new("/home/user/project_workspace/source_files");
    let mut output = String::new();

    if let Ok(entries) = fs::read_dir(dir) {
        let mut files: Vec<_> = entries.filter_map(Result::ok).collect();
        files.sort_by_key(|e| e.file_name());

        for entry in files {
            let path = entry.path();
            if path.is_file() {
                let file_name = path.file_name().unwrap().to_str().unwrap();
                let deps = process_file(&path); // Needs fixing
                for dep in deps {
                    output.push_str(&format!("{} {}\n", file_name, dep));
                }
            }
        }
    }

    let hex_output: String = output.as_bytes().iter().map(|b| format!("{:02x}", b)).collect();
    fs::write("/home/user/project_workspace/deps.hex", hex_output).unwrap();
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
