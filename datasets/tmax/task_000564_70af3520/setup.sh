#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make nginx cargo curl binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    char buffer[64];
    strcpy(buffer, argv[1]);
    printf("42\n");
    return 0;
}
EOF
    gcc /app/legacy_calc.c -o /app/legacy_calc
    strip -s /app/legacy_calc
    rm /app/legacy_calc.c

    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil
    echo "3 + 4 * (2 - 1)" > /home/user/corpora/clean/clean1.txt
    echo "10 / 2" > /home/user/corpora/clean/clean2.txt

    python3 -c "print('A' * 70)" > /home/user/corpora/evil/evil1.txt
    echo "5 + 5; rm -rf /" > /home/user/corpora/evil/evil2.txt
    echo "((((((1))))))" > /home/user/corpora/evil/evil3.txt

    mkdir -p /home/user/project
    touch /home/user/project/filter.c

    cd /home/user/project
    cargo new service
    cat << 'EOF' > /home/user/project/service/src/main.rs
use std::os::raw::{c_char, c_int};

extern "C" {
    fn validate_math(expr: *const c_char) -> c_int;
}

fn main() {
    let mut buffer = String::new();
    let r = &buffer;
    buffer.push_str("test"); // Borrow checker error
    println!("{}", r);
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
