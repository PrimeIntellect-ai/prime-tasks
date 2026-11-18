#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo build-essential
    pip3 install pytest

    mkdir -p /home/user
    cargo new --lib /home/user/poly-parser

    cat << 'EOF' >> /home/user/poly-parser/Cargo.toml
[build-dependencies]
cc = "1.0"
EOF

    mkdir -p /home/user/poly-parser/src/c_src
    cat << 'EOF' > /home/user/poly-parser/src/c_src/fast_parse.c
int sum_ascii_values(const char* buf, int len) {
    int sum = 0;
    for(int i = 0; i < len; i++) {
        sum += buf[i];
    }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/poly-parser/src/lib.rs
extern "C" {
    fn sum_ascii_values(buf: *const u8, len: i32) -> i32;
}

pub fn process_data(data: &str) -> i32 {
    let mut s = String::with_capacity(64);
    s.push_str(data);
    unsafe {
        // BUG: Passing capacity instead of length reads uninitialized memory!
        sum_ascii_values(s.as_ptr(), s.capacity() as i32)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_process() {
        assert_eq!(process_data("abc"), 294); // 97 + 98 + 99
    }
}
EOF

    touch /home/user/poly-parser/build.rs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
