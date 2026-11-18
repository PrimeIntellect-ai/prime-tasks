#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        cargo \
        rustc \
        cron \
        curl
    pip3 install pytest

    mkdir -p /app/anonymizer_lib/src

    cat << 'EOF' > /app/anonymizer_lib/Cargo.toml
[package]
name = "anonymizer_lib"
version = "0.1.0"
edition = "2021"

[dependencies]
# regex dependency deliberately omitted
EOF

    cat << 'EOF' > /app/anonymizer_lib/src/lib.rs
use regex::Regex;

pub fn mask_pii(_user: &str, _ip: &str) -> (String, String) {
    let _re = Regex::new(r".*").unwrap();
    ("***".to_string(), "0.0.0.0".to_string())
}
EOF

    cat << 'EOF' > /app/oracle_processor
#!/usr/bin/env python3
import sys

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    parts = line.split(';')
    data = {}
    for p in parts:
        if ':' in p:
            k, v = p.split(':', 1)
            data[k] = v

    if 'ID' not in data:
        continue

    id_val = data['ID']
    user = '***'
    ip = '0.0.0.0'

    s = []
    for k in ['S1', 'S2', 'S3']:
        val = data.get(k, 'NA')
        if val == 'NA':
            s.append(None)
        else:
            s.append(float(val))

    nones = s.count(None)
    if nones == 1:
        avg = sum([x for x in s if x is not None]) / 2.0
        s = [avg if x is None else x for x in s]
    elif nones == 2:
        val = sum([x for x in s if x is not None])
        s = [val if x is None else x for x in s]
    elif nones == 3:
        s = [0.0, 0.0, 0.0]

    print(f"{id_val},{user},{ip},S1,{s[0]:.2f}")
    print(f"{id_val},{user},{ip},S2,{s[1]:.2f}")
    print(f"{id_val},{user},{ip},S3,{s[2]:.2f}")
EOF
    chmod +x /app/oracle_processor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
