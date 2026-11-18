#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/libwebcrypto
    cd /home/user/libwebcrypto

    cat << 'EOF' > webcrypto.c
int encrypt() { return 42; }
EOF

    gcc -shared -fPIC -o libwebcrypto.so.1.2.0 webcrypto.c
    gcc -shared -fPIC -o libwebcrypto.so.1.3.4 webcrypto.c
    gcc -shared -fPIC -o libwebcrypto.so.1.3.5 webcrypto.c
    gcc -shared -fPIC -o libwebcrypto.so.2.0.0 webcrypto.c
    rm webcrypto.c

    mkdir -p /home/user/web_sec_tool/src
    cd /home/user/web_sec_tool

    cat << 'EOF' > Cargo.toml
[package]
name = "web_sec_tool"
version = "0.1.0"
edition = "2021"

[dependencies]
regex = "1.8.0"
EOF

    cat << 'EOF' > build.rs
fn main() {
    println!("cargo:rustc-link-search=native=/home/user/libwebcrypto");
    println!("cargo:rustc-link-lib=dylib=webcrypto");
}
EOF

    cat << 'EOF' > src/main.rs
extern "C" {
    fn encrypt() -> i32;
}

fn main() {
    let val = unsafe { encrypt() };
    println!("Encrypted value: {}", val);
}
EOF

    chown -R user:user /home/user/libwebcrypto /home/user/web_sec_tool
    chmod -R 777 /home/user
