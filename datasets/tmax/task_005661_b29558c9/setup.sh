#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ci_data

    cat << 'EOF' > /home/user/ci_data/build.log
Triggered by: https://ci.example.com/webhook?repo=backend&commit_sha=f9a8b7c6&branch=develop&user=admin
Compiling rust_project v0.1.0
error[E0382]: use of moved value: `config`
  --> src/main.rs:42:15
   |
41 |     let config = load_config();
   |         ------ move occurs because `config` has type `Config`, which does not implement the `Copy` trait
42 |     process(config);
   |             ^^^^^^ value used here after move
EOF

    cat << 'EOF' > /home/user/ci_data/metrics.txt
test_duration=15+25*4
coverage=850/10
EOF

    cat << 'EOF' > /home/user/ci_data/Makefile.broken
all: main.c
    gcc -wall -o app main.c
EOF

    chown -R user:user /home/user/ci_data
    chmod -R 777 /home/user
