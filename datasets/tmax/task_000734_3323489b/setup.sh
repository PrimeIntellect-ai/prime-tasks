#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo build-essential
    pip3 install pytest

    mkdir -p /home/user/rust_ffi_project
    cd /home/user/rust_ffi_project
    cargo new --lib sorter

    cat << 'EOF' > /home/user/rust_ffi_project/sorter/Cargo.toml
[package]
name = "sorter"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/rust_ffi_project/sorter/src/lib.rs
// Intentional bugs: Missing #[no_mangle], missing extern "C", missing cdylib in Cargo.toml
pub fn merge_sort_ffi(data: *mut i32, len: usize) {
    if data.is_null() || len == 0 { return; }
    let slice = unsafe { std::slice::from_raw_parts_mut(data, len) };
    let mut temp = slice.to_vec();
    merge_sort(slice, &mut temp);
}

pub fn quick_sort_ffi(data: *mut i32, len: usize) {
    if data.is_null() || len == 0 { return; }
    let slice = unsafe { std::slice::from_raw_parts_mut(data, len) };
    slice.sort_unstable();
}

fn merge_sort(arr: &mut [i32], temp: &mut [i32]) {
    let len = arr.len();
    if len <= 1 {
        return;
    }
    let mid = len / 2;
    merge_sort(&mut arr[..mid], &mut temp[..mid]);
    merge_sort(&mut arr[mid..], &mut temp[mid..]);

    let mut left = 0;
    let mut right = mid;
    let mut out = 0;

    while left < mid && right < len {
        if arr[left] <= arr[right] {
            temp[out] = arr[left];
            left += 1;
        } else {
            temp[out] = arr[right];
            right += 1;
        }
        out += 1;
    }

    while left < mid {
        temp[out] = arr[left];
        left += 1;
        out += 1;
    }
    while right < len {
        temp[out] = arr[right];
        right += 1;
        out += 1;
    }

    arr.copy_from_slice(&temp[..len]);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
