#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make cargo rustc golang
    pip3 install pytest

    mkdir -p /home/user/project/libmath
    mkdir -p /home/user/project/rs_calc/src
    mkdir -p /home/user/project/go_machine

    cat << 'EOF' > /home/user/project/libmath/prime.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int is_prime(int n) {
    if (n <= 1) return 0;
    if (n <= 3) return 1;
    if (n % 2 == 0 || n % 3 == 0) return 0;
    for (int i = 5; i * i <= n; i = i + 6)
        if (n % i == 0 || n % (i + 2) == 0)
            return 0;
    return 1;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int target = atoi(argv[1]);
    int count = 0;
    int current = 1;
    // use math.h just to force the -lm requirement
    double dummy = sqrt(16.0); 
    while (count < target) {
        current++;
        if (is_prime(current)) {
            count++;
        }
    }
    printf("%d\n", current);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/libmath/Makefile
prime: prime.c
    gcc -O2 prime.c -o prime
EOF

    cat << 'EOF' > /home/user/project/rs_calc/Cargo.toml
[package]
name = "rs_calc"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /home/user/project/rs_calc/src/main.rs
use std::env;

fn get_factors_msg(n: u32) -> &'static str {
    let mut count = 0;
    let mut num = n;
    let mut d = 2;
    while num > 1 {
        if num % d == 0 {
            count += 1;
            while num % d == 0 {
                num /= d;
            }
        }
        d += 1;
        if d * d > num && num > 1 {
            count += 1;
            break;
        }
    }

    // Borrow checker error: returning a reference to a locally formatted String
    let s = format!("{}", count);
    &s 
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 2 {
        std::process::exit(1);
    }
    let n: u32 = args[1].parse().unwrap();
    println!("{}", get_factors_msg(n));
}
EOF

    cat << 'EOF' > /home/user/project/go_machine/go.mod
module gomachine

go 1.21
EOF

    cat << 'EOF' > /home/user/project/go_machine/main.go
package main

import (
	"fmt"
)

func main() {
	fmt.Println("Implement the state machine here.")
}
EOF

    cat << 'EOF' > /home/user/project/program.math
ADD 15
PRIME 6
FACTORS 30
MUL 2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
