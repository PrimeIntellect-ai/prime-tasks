#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo rustc
pip3 install pytest

# Create directories and dummy files
mkdir -p /home/user/data1/folderA
mkdir -p /home/user/data1/folderB
mkdir -p /home/user/data2/folderC

# Create precise dummy files
dd if=/dev/zero of=/home/user/data1/folderA/file1.bin bs=1024 count=15 2>/dev/null
dd if=/dev/zero of=/home/user/data1/folderB/file2.bin bs=1024 count=20 2>/dev/null
dd if=/dev/zero of=/home/user/data2/folderC/file3.bin bs=1024 count=40 2>/dev/null

# Create infinite symlink loop
ln -s /home/user/data1/folderA /home/user/data1/folderB/linkA
ln -s /home/user/data1/folderB /home/user/data1/folderA/linkB

# Create the config file
cat << 'EOF' > /home/user/backup_config.conf
# Backup Configuration File
# Define target directories below

SCAN_DIR=/home/user/data1
# SCAN_DIR=/home/user/skip_this

SCAN_DIR=/home/user/data2
EOF

# Create the Rust project
cd /home/user
cargo new scanner
cd scanner

# Write the buggy Rust code
cat << 'EOF' > src/main.rs
use std::env;
use std::fs;
use std::path::Path;

fn get_dir_size(path: &Path) -> u64 {
    let mut total_size = 0;
    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries.flatten() {
            let path = entry.path();
            // BUG: Using fs::metadata follows symlinks, causing infinite loops
            if let Ok(metadata) = fs::metadata(&path) {
                if metadata.is_dir() {
                    total_size += get_dir_size(&path);
                } else {
                    total_size += metadata.len();
                }
            }
        }
    }
    total_size
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    for dir in args {
        let path = Path::new(&dir);
        if path.exists() {
            let size = get_dir_size(path);
            println!("{} - Total size: {} bytes", dir, size);
        } else {
            println!("{} - Does not exist", dir);
        }
    }
}
EOF

# Create the user
useradd -m -s /bin/bash user || true

# Set permissions
chown -R user:user /home/user
chmod -R 777 /home/user
