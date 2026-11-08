#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest packaging

    mkdir -p /home/user/project
    cat << 'EOF' > /home/user/project/main.rs
mod magic;

fn main() {
    println!("The magic number is: {}", magic::MAGIC_NUMBER);
}
EOF

    cat << 'EOF' > /home/user/project/ops.txt
1.0.9 ADD 500
2.1.0 ADD 15
2.0.99 MUL 100
2.10.0 LSHIFT 3
3.0.0 XOR 42
10.0.0 SUB 2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
