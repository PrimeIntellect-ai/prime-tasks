#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc rustc binutils
    pip3 install pytest

    mkdir -p /home/user/project/src \
             /home/user/project/scripts \
             /home/user/project/data \
             /home/user/project/build \
             /home/user/project/output

    cat << 'EOF' > /home/user/project/src/math_ops.c
int add(int a, int b) {
    return a + b;
}
EOF

    cat << 'EOF' > /home/user/project/src/lib.rs
extern "C" {
    fn add(a: i32, b: i32) -> i32;
}

#[no_mangle]
pub extern "C" fn compute(data: *const i32, len: usize) -> i32 {
    let slice = unsafe { std::slice::from_raw_parts(data, len) };
    let mut sum = 0;
    let s1 = &mut sum;
    let s2 = &mut sum; // Borrow checker error
    for &val in slice {
        *s1 = unsafe { add(*s2, val) };
    }
    sum
}
EOF

    cat << 'EOF' > /home/user/project/scripts/run.py
import ctypes
import os

# Needs to be updated to correct path and handle dependency
lib = ctypes.CDLL("./librust_compute.so")

lib.compute.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_size_t]
lib.compute.restype = ctypes.c_int

def run_test(arr, name):
    ArrayType = ctypes.c_int * len(arr)
    c_arr = ArrayType(*arr)
    res = lib.compute(c_arr, len(arr))
    print(f"{name}: {res}")

run_test([1, 2, 3], "TestA")
run_test([10, 20, 30], "TestC")
run_test([-5, 5, 10], "TestB")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
