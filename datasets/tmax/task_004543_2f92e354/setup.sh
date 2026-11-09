#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc rustc
    pip3 install pytest

    mkdir -p /home/user/project/c_src
    mkdir -p /home/user/project/rust_src

    cat << 'EOF' > /home/user/project/c_src/ops.c
int multiply(int a, int b) {
    return a * b;
}
EOF

    cat << 'EOF' > /home/user/project/rust_src/main.rs
#[link(name = "mathops")]
extern {
    fn multiply(a: i32, b: i32) -> i32;
}

fn parse_and_calc(expr: &String) -> i32 {
    let parts: Vec<&str> = expr.split_whitespace().collect();
    if parts.len() == 5 {
        let a: i32 = parts[0].parse().unwrap();
        let b: i32 = parts[2].parse().unwrap();
        let c: i32 = parts[4].parse().unwrap();
        let mult_res = unsafe { multiply(b, c) };
        a + mult_res
    } else {
        0
    }
}

fn main() {
    let expr = String::from("10 + 20 * 3");
    let s = expr; // Value moved here
    let res = parse_and_calc(&expr); // Borrow checker error
    println!("{}", res);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
