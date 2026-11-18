#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential sqlite3 libsqlite3-dev pkg-config
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH=/opt/rust/bin:$PATH

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
id,text
1,Hello world
2,The quick brown fox
3,Jumps over the lazy dog
42,Data science is fascinating because it allows us to uncover hidden patterns
73,Aaaa Eeee Iii Oooo Uuuu
88,Fascinating data patterns uncovered
99,Random text with no vowels rst lnm
EOF

    chmod -R 777 /home/user
    chmod -R 777 /opt/rust
