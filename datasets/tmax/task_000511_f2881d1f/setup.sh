#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest pytest-mock

    mkdir -p /home/user/rust_data_ext/src
    mkdir -p /home/user/python_processor/tests

    cat << 'EOF' > /home/user/rust_data_ext/Cargo.toml
[package]
name = "rust_data_ext"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/rust_data_ext/src/lib.rs
#[no_mangle]
pub extern "C" fn normalize_and_sum(data: *mut f64, len: usize) -> f64 {
    if data.is_null() || len == 0 {
        return 0.0;
    }

    let slice = unsafe { std::slice::from_raw_parts_mut(data, len) };

    let mut sum = 0.0;
    let mut max_val = 0.0_f64;

    for val in slice.iter() {
        sum += *val;
        if *val > max_val {
            max_val = *val;
        }
    }

    // BUG: borrow checker error. We try to use an immutable reference inside a mutable iteration incorrectly, or similarly.
    // Let's create a clear borrow checker error:
    let first_ref = &slice[0];
    for val in slice.iter_mut() {
        if max_val > 0.0 {
            *val = *val / max_val;
        }
    }
    // usage of first_ref after mutable borrow
    let _dummy = *first_ref;

    sum
}
EOF

    cat << 'EOF' > /home/user/python_processor/wrapper.py
import ctypes
import os

# Load the shared library
lib_path = os.path.join(os.path.dirname(__file__), 'libdataparser.so')
lib = ctypes.CDLL(lib_path)

# ABI mapping (BUG: types are wrong)
# Rust signature: pub extern "C" fn normalize_and_sum(data: *mut f64, len: usize) -> f64
lib.normalize_and_sum.argtypes = [ctypes.POINTER(ctypes.c_float), ctypes.c_int]
lib.normalize_and_sum.restype = ctypes.c_float

def normalize_and_sum(data_list):
    arr_type = ctypes.c_double * len(data_list)
    arr = arr_type(*data_list)

    result = lib.normalize_and_sum(arr, len(data_list))

    # Update Python list with mutated values
    for i in range(len(data_list)):
        data_list[i] = arr[i]

    return result
EOF

    cat << 'EOF' > /home/user/python_processor/app.py
from wrapper import normalize_and_sum

def report_analytics(total_sum):
    # Imagine this sends data to a remote server
    print(f"Reporting sum: {total_sum}")

def process_data(data_list):
    total = normalize_and_sum(data_list)
    report_analytics(total)
    return total
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
