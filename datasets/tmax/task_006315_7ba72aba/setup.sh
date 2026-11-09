#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc rustc patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/polyglot_project
    cd /home/user/polyglot_project

    cat << 'EOF' > worker.c
#include <stdio.h>
int main() {
    int arr[5] = {1, 2, 3, 4, 5};
    int sum = 0;
    // UB: accessing arr[5]
    for (int i = 0; i <= 5; i++) {
        sum += arr[i];
    }
    printf("Sum: %d\n", sum);
    return 0;
}
EOF

    cat << 'EOF' > parser.rs
fn main() {
    let mut s = String::from("hello");
    let r1 = &s;
    let r2 = &mut s;

    println!("Read: {}", r1);
    r2.push_str(" world");
    println!("Write: {}", r2);
}
EOF

    cat << 'EOF' > e2e_test.py
import subprocess
import sys

def run_test():
    try:
        worker_out = subprocess.check_output(['./worker'], text=True).strip()
        assert worker_out == "Sum: 15", f"Worker failed: {worker_out}"

        parser_out = subprocess.check_output(['./parser'], text=True).strip()
        assert parser_out == "Read: hello\nWrite: hello world", f"Parser failed: {parser_out}"

        print("E2E TESTS PASSED")
    except Exception as e:
        print(f"E2E TESTS FAILED: {e}")
        sys.exit(1)

if __name__ == "__main__":
    run_test()
EOF

    chmod -R 777 /home/user
