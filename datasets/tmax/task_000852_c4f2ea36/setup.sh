#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/cypher_degree_calc
#!/usr/bin/env python3
import sys
import json
import re

stats = {}
for line in sys.stdin:
    m = re.search(r'MATCH \(n1:Person \{id: (\d+)\}\)-\[:KNOWS\]->\(n2:Person \{id: (\d+)\}\)', line)
    if m:
        u, v = m.groups()
        if u not in stats: stats[u] = {"in": 0, "out": 0}
        if v not in stats: stats[v] = {"in": 0, "out": 0}
        stats[u]["out"] += 1
        stats[v]["in"] += 1

print(json.dumps(stats, separators=(',', ':')))
EOF
    chmod +x /opt/oracle/cypher_degree_calc

    mkdir -p /app/cypher_analyzer/src
    cat << 'EOF' > /app/cypher_analyzer/Cargo.toml
[package]
name = "cypher_analyzer"
version = "1.0.0"
edition = "2021"

[dependencies]
# Missing serde and serde_json
EOF

    cat << 'EOF' > /app/cypher_analyzer/src/main.rs
use std::io::{self, BufRead};
use std::collections::HashMap;

fn main() {
    let stdin = io::stdin();
    let mut stats: HashMap<String, (u32, u32)> = HashMap::new();

    for line in stdin.lock().lines() {
        let line = line.unwrap();
        if line.len() >= 49 {
            // Buggy extraction assuming single digits
            let u = &line[22..23];
            let v = &line[48..49];

            let u_entry = stats.entry(u.to_string()).or_insert((0, 0));
            u_entry.1 += 1; // out

            let v_entry = stats.entry(v.to_string()).or_insert((0, 0));
            v_entry.0 += 1; // in
        }
    }

    print!("{}", "{");
    let mut first = true;
    for (k, (in_d, out_d)) in stats {
        if !first { print!(","); }
        print!("\"{}\":{}", k, "{");
        print!("\"in\":{},\"out\":{}", in_d, out_d);
        print!("{}", "}");
        first = false;
    }
    println!("{}", "}");
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
