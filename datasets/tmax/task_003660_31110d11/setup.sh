#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo golang-go make gcc
    pip3 install pytest

    mkdir -p /app/divsum-0.1.0/src
    mkdir -p /app/go-worker

    cat << 'EOF' > /app/divsum-0.1.0/Cargo.toml
[package]
name = "divsum"
version = "0.1.0"
edition = "2021"

[lib]
name = "divsum"
EOF

    cat << 'EOF' > /app/divsum-0.1.0/src/lib.rs
#[no_mangle]
pub extern "C" fn sum_of_divisors(n: u64) -> u64 {
    let mut sum = 0;
    let r = &mut sum;
    for i in 1..=(n / 2) {
        if n % i == 0 {
            sum += i; // Error: cannot mutate `sum` while it is borrowed by `r`
            *r += 0;
        }
    }
    sum + n
}
EOF

    python3 -c "import json; data = [10000000 + i for i in range(50)]; open('/app/input.json', 'w').write(json.dumps(data))"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
