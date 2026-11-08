#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc rustc socat curl binutils
    pip3 install pytest

    mkdir -p /home/user/matrix_app/libs
    mkdir -p /home/user/matrix_app/src

    # Create C sources with specific function sizes using assembly
    cat << 'EOF' > /home/user/matrix_app/libs/v1.s
.text
.globl compute_matrix
.type compute_matrix, @function
compute_matrix:
    .space 64, 0x90
    ret
.size compute_matrix, .-compute_matrix
EOF

    cat << 'EOF' > /home/user/matrix_app/libs/v2.s
.text
.globl compute_matrix
.type compute_matrix, @function
compute_matrix:
    .space 127, 0x90
    ret
.size compute_matrix, .-compute_matrix
EOF

    cat << 'EOF' > /home/user/matrix_app/libs/v3.s
.text
.globl compute_matrix
.type compute_matrix, @function
compute_matrix:
    .space 255, 0x90
    ret
.size compute_matrix, .-compute_matrix
EOF

    gcc -shared -fPIC /home/user/matrix_app/libs/v1.s -o /home/user/matrix_app/libs/libcompute_v1.so
    gcc -shared -fPIC /home/user/matrix_app/libs/v2.s -o /home/user/matrix_app/libs/libcompute_v2.so
    gcc -shared -fPIC /home/user/matrix_app/libs/v3.s -o /home/user/matrix_app/libs/libcompute_v3.so

    rm /home/user/matrix_app/libs/*.s

    # Create the Rust source code with a borrow checker error
    cat << 'EOF' > /home/user/matrix_app/src/main.rs
use std::io::Write;
use std::net::TcpListener;

#[link(name = "compute")]
extern "C" {
    fn compute_matrix();
}

fn main() {
    let msg = String::from("HTTP/1.1 200 OK\r\n\r\nMatrix Computed");
    let moved_msg = msg; // move happens here

    // Borrow checker error: using moved value 'msg'
    println!("Server starting with message: {}", msg);

    let listener = TcpListener::bind("127.0.0.1:8000").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        unsafe {
            compute_matrix();
        }
        stream.write_all(moved_msg.as_bytes()).unwrap();
        break; // Only handle one request for easy testing
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/matrix_app
    chmod -R 777 /home/user
