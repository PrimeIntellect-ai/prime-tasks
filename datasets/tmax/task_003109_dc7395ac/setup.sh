#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        curl \
        gcc-aarch64-linux-gnu \
        cargo \
        netcat-openbsd

    pip3 install pytest

    mkdir -p /home/user/project/src/c_src
    mkdir -p /home/user/project/.cargo

    cat << 'EOF' > /home/user/project/Cargo.toml
[package]
name = "ws-edge-processor"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/project/src/c_src/processor.c
int process_data(int* data, int len) {
    int sum = 0;
    for(int i=0; i<len; i++) { sum += data[i]; }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/project/src/main.rs
extern "C" {
    fn process_data(data: *const i32, len: usize) -> i32;
}
fn main() {
    println!("Server running");
}
EOF

    cat << 'EOF' > /home/user/project/build.sh
#!/bin/bash
# BUGGY BUILD SCRIPT
cd src/c_src
gcc -c processor.c -o processor.o
ar rcs libprocessor.a processor.o
cd ../..
cargo build --target aarch64-unknown-linux-gnu
EOF
    chmod +x /home/user/project/build.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
