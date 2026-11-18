#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev cargo curl
    pip3 install pytest

    mkdir -p /home/user/hybrid_image_filter/c_src
    mkdir -p /home/user/hybrid_image_filter/src

    cat << 'EOF' > /home/user/hybrid_image_filter/Cargo.toml
[package]
name = "hybrid_image_filter"
version = "0.1.0"
edition = "2021"
build = "build.rs"

[dependencies]
libc = "0.2"

[build-dependencies]
cc = "1.0"
EOF

    cat << 'EOF' > /home/user/hybrid_image_filter/build.rs
use std::process::Command;
fn main() {
    let status = Command::new("gcc")
        .args(&["-g", "c_src/sanity_check.c", "c_src/filter.c", "-o", "sanity_check_bin"])
        .status()
        .expect("Failed to compile sanity check");
    assert!(status.success());

    let run_status = Command::new("./sanity_check_bin")
        .status()
        .expect("Failed to run sanity check");
    assert!(run_status.success(), "Sanity check failed (segfault/error)");

    cc::Build::new()
        .file("c_src/filter.c")
        .compile("filter");
}
EOF

    cat << 'EOF' > /home/user/hybrid_image_filter/src/lib.rs
extern crate libc;
use libc::c_int;

extern "C" {
    pub fn apply_filter(pixels: *mut c_int, width: c_int, height: c_int) -> *mut c_int;
    pub fn free_image(pixels: *mut c_int);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ptr;

    #[test]
    fn test_filter() {
        let mut pixels = vec![1, 2, 3, 4];
        unsafe {
            let res = apply_filter(pixels.as_mut_ptr(), 2, 2);
            assert!(!res.is_null());
            free_image(res);
        }
    }
}
EOF

    cat << 'EOF' > /home/user/hybrid_image_filter/c_src/filter.c
#include <stdlib.h>

int* apply_filter(int* pixels, int width, int height) {
    // BUG 1: Allocating wrong size (missing sizeof(int))
    int* new_pixels = (int*)malloc(width * height);
    if (!new_pixels) return NULL;

    int* temp_buffer = (int*)malloc(width * height * sizeof(int));

    // BUG 2: Off by one error (<= instead of <)
    for (int i = 0; i <= width * height; i++) {
        temp_buffer[i] = pixels[i] * 2;
    }

    for (int i = 0; i < width * height; i++) {
        new_pixels[i] = temp_buffer[i];
    }

    // BUG 3: Memory leak of temp_buffer
    // free(temp_buffer);

    return new_pixels;
}

void free_image(int* pixels) {
    free(pixels);
}
EOF

    cat << 'EOF' > /home/user/hybrid_image_filter/c_src/sanity_check.c
#include <stdlib.h>
#include <stdio.h>

extern int* apply_filter(int*, int, int);
extern void free_image(int*);

int main() {
    int w = 10, h = 10;
    int* pixels = (int*)malloc(w * h * sizeof(int));
    for(int i=0; i<w*h; i++) pixels[i] = i;

    int* out = apply_filter(pixels, w, h);
    if (!out) return 1;

    free_image(out);
    free(pixels);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/hybrid_image_filter/c_src/bench.c
#include <stdlib.h>
#include <stdio.h>
#include <time.h>

extern int* apply_filter(int*, int, int);
extern void free_image(int*);

int main() {
    int w = 100, h = 100;
    int* pixels = (int*)malloc(w * h * sizeof(int));

    clock_t start = clock();
    for(int k=0; k<1000; k++) {
        int* out = apply_filter(pixels, w, h);
        free_image(out);
    }
    clock_t end = clock();

    double ms = ((double)(end - start) / CLOCKS_PER_SEC) * 1000.0;
    printf("%.0f\n", ms);
    free(pixels);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/hybrid_image_filter
    chmod -R 777 /home/user
