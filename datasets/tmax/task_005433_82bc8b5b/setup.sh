#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/utility/rust_lib/src

    cat << 'EOF' > /home/user/utility/rust_lib/Cargo.toml
[package]
name = "rust_lib"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/utility/rust_lib/src/lib.rs
#[no_mangle]
pub extern "C" fn process_deps() {
    let mut base = String::from("deps_");
    let r = &base;
    base.push_str("loaded");
    // Borrow checker error: immutable borrow `r` used after mutable borrow `push_str`
    println!("Status: {}", r);
}
EOF

    cat << 'EOF' > /home/user/utility/deps.txt
libalpha: libbeta libgamma
libbeta: libdelta
libgamma: libdelta
libdelta:
librust_lib: libalpha
EOF

    cat << 'EOF' > /home/user/utility/resolver.py
import sys

def parse_and_sort(filepath):
    # TODO: Implement expression parsing, dependency graph creation,
    # and topologically sort the libraries.
    # Return a list of library names.
    pass

if __name__ == '__main__':
    order = parse_and_sort('deps.txt')
    if order:
        with open('load_order.txt', 'w') as f:
            f.write(", ".join(order))
EOF

    chown -R user:user /home/user/utility
    chmod -R 777 /home/user
