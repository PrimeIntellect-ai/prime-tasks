#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    export PATH=/usr/local/cargo/bin:$PATH
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

    mkdir -p /home/user/model_artifacts
    dd if=/dev/urandom of=/home/user/model_artifacts/model_A.bin bs=1M count=5 status=none
    dd if=/dev/urandom of=/home/user/model_artifacts/model_B.bin bs=1M count=12 status=none

    cat << 'EOF' > /home/user/inference_benchmarks.csv
text_sample,latency_ms
"hello world",45.5
"this is a longer sample for tokenization",52.0
"rust is fast",48.2
EOF

    cd /home/user
    cargo new mlops_tracker

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /usr/local/cargo /usr/local/rustup
