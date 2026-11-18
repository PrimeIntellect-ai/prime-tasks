#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/organizer/src

    cat << 'EOF' > /home/user/input_files.json
[
  {"name": "file1.js", "size": 150, "tags": ["frontend", "react"]},
  {"name": "file2.js", "size": 200, "tags": ["backend", "node"]},
  {"name": "file3.js", "size": 150, "tags": ["frontend", "vue"]},
  {"name": "file4.js", "size": 50, "tags": ["config"]},
  {"name": "file5.js", "size": 300, "tags": ["database", "sql"]},
  {"name": "file6.js", "size": 100, "tags": ["backend", "node"]}
]
EOF

    cat << 'EOF' > /home/user/rules.json
{
  "max_size": 400,
  "conflicts": [
    ["react", "vue"],
    ["frontend", "database"]
  ]
}
EOF

    cat << 'EOF' > /home/user/organizer/Cargo.toml
[package]
name = "organizer"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

[dev-dependencies]
proptest = "1.0"
EOF

    cat << 'EOF' > /home/user/organizer/src/main.rs
use organizer::{organize_files, FileItem, Rules};
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 {
        eprintln!("Usage: organizer <input_files.json> <rules.json> <output.json>");
        std::process::exit(1);
    }

    let files_data = fs::read_to_string(&args[1]).unwrap();
    let rules_data = fs::read_to_string(&args[2]).unwrap();

    let mut files: Vec<FileItem> = serde_json::from_str(&files_data).unwrap();
    let rules: Rules = serde_json::from_str(&rules_data).unwrap();

    let bins = organize_files(&mut files, &rules);

    let bin_names: Vec<Vec<String>> = bins
        .into_iter()
        .map(|bin| bin.into_iter().map(|f| f.name).collect())
        .collect();

    let output_data = serde_json::to_string_pretty(&bin_names).unwrap();
    fs::write(&args[3], output_data).unwrap();
}
EOF

    cat << 'EOF' > /home/user/organizer/src/lib.rs
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileItem {
    pub name: String,
    pub size: u32,
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Rules {
    pub max_size: u32,
    pub conflicts: Vec<[String; 2]>,
}

pub fn organize_files(files: &mut Vec<FileItem>, rules: &Rules) -> Vec<Vec<FileItem>> {
    // Sort files: size descending, then name ascending
    files.sort_by(|a, b| {
        b.size.cmp(&a.size).then_with(|| a.name.cmp(&b.name))
    });

    let mut bins: Vec<Vec<&FileItem>> = Vec::new();

    for file in files.iter() {
        let mut placed = false;

        for bin in bins.iter_mut() {
            let current_size: u32 = bin.iter().map(|f| f.size).sum();
            if current_size + file.size <= rules.max_size {

                let mut conflict = false;
                for existing_file in bin.iter() {
                    for tag1 in &file.tags {
                        for tag2 in &existing_file.tags {
                            for rule in &rules.conflicts {
                                if (&rule[0] == tag1 && &rule[1] == tag2) || 
                                   (&rule[0] == tag2 && &rule[1] == tag1) {
                                    conflict = true;
                                }
                            }
                        }
                    }
                }

                if !conflict {
                    bin.push(file); // borrow checker error: file does not live long enough
                    placed = true;
                    break;
                }
            }
        }

        if !placed {
            bins.push(vec![file]);
        }
    }

    // Convert Vec<Vec<&FileItem>> to Vec<Vec<FileItem>>
    bins.into_iter()
        .map(|bin| bin.into_iter().map(|f| f.clone()).collect())
        .collect()
}

// TODO: Add proptest here
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
