#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install dependencies
    apt-get install -y rustc cargo tesseract-ocr imagemagick fonts-dejavu-core

    mkdir -p /app

    # Generate the policy memo image
    convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 20 -fill black -annotate +20+40 "ATTENTION BACKUP ADMINS:\nEffective immediately, all archived files must be prefixed with the code DEPT_SEC_77X_.\nAny file attempting a Zip Slip directory traversal must be isolated.\nDo not extract them to the root. Place the isolated files directly in /archive/quarantine/\nEnd of memo." /app/policy_memo.png

    # Create the oracle sanitizer in Rust
    mkdir -p /app/oracle
    cd /app/oracle
    cargo init --bin
    cat << 'EOF' > src/main.rs
use std::io::{self, Read};
use std::path::{Path, PathBuf, Component};

fn normalize_path(path: &Path) -> PathBuf {
    let mut components = Vec::new();
    for component in path.components() {
        match component {
            Component::Prefix(_) | Component::RootDir => {
                components.clear();
                components.push(Component::RootDir);
            }
            Component::CurDir => {}
            Component::ParentDir => {
                if let Some(last) = components.last() {
                    if *last != Component::RootDir {
                        components.pop();
                    }
                }
            }
            Component::Normal(c) => {
                components.push(Component::Normal(c));
            }
        }
    }
    components.into_iter().collect()
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();

    for block in input.split("---") {
        let block = block.trim();
        if block.is_empty() {
            continue;
        }
        for line in block.lines() {
            if line.starts_with("File: ") {
                let filepath = line[6..].trim();
                let path = Path::new(filepath);
                let basename = path.file_name().unwrap_or_default().to_string_lossy();
                let new_basename = format!("DEPT_SEC_77X_{}", basename);

                let mut full_path = PathBuf::from("/archive/");
                full_path.push(path);

                let resolved = normalize_path(&full_path);
                let archive_root = Path::new("/archive");

                if resolved.starts_with(archive_root) {
                    let rel = resolved.strip_prefix(archive_root).unwrap();
                    let mut final_path = archive_root.to_path_buf();
                    if let Some(parent) = rel.parent() {
                        if parent.as_os_str() != "" {
                            final_path.push(parent);
                        }
                    }
                    final_path.push(new_basename);
                    println!("{}", final_path.display());
                } else {
                    println!("/archive/quarantine/{}", new_basename);
                }
            }
        }
    }
}
EOF
    cargo build --release
    cp target/release/oracle /app/oracle_sanitizer
    chmod +x /app/oracle_sanitizer

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the expected cargo project directory for the user
    mkdir -p /home/user/sanitizer

    chmod -R 777 /home/user
