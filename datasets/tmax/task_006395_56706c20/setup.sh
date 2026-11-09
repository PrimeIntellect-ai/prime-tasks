#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.txt
The quick brown fox jumps over the lazy dog.
A quick brown dog outpaces a quick fox.
The lazy fox is not as quick as the brown dog.
Data science requires statistical thinking and probabilistic modeling.
Bayesian inference provides a principled way to update beliefs.
Bootstrap sampling allows us to estimate the sampling distribution.
Tokenization is the first step in natural language processing.
Feature engineering extracts informative signals from raw data.
The fox and the dog are friends.
A lazy dog sleeps all day.
EOF

    # Make Rust available to all users by copying to /usr/local or adjusting bashrc
    # Actually, simpler to just install rustup for the user or globally.
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust
    ln -s /opt/rust/bin/* /usr/local/bin/

    chmod -R 777 /home/user
