#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang cargo gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/test_env/rust_src/src
    mkdir -p /home/user/test_env/go_app

    cat << 'EOF' > /home/user/test_env/rust_src/Cargo.toml
[package]
name = "version_check"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/test_env/rust_src/src/lib.rs
use std::ffi::CString;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn get_version() -> *const c_char {
    let ver = CString::new("1.5.2").unwrap();
    ver.as_ptr() // Bug: returning pointer to local variable that gets dropped
}
EOF

    cat << 'EOF' > /home/user/test_env/go_app/main.go
package main

/*
#cgo LDFLAGS: -L../rust_src/target/debug -lversion_check
#include <stdlib.h>

const char* get_version();
*/
import "C"

func GetVersion() string {
    return C.GoString(C.get_version())
}
EOF

    cat << 'EOF' > /home/user/test_env/go_app/parser_test.go
package main

import (
    "os"
    "testing"
)

func TestVersionParser(t *testing.T) {
    if os.Getenv("STRICT_SEMVER") != "1" {
        t.Fatal("Test fixture requires STRICT_SEMVER=1")
    }

    v := GetVersion()
    if v != "1.5.2" {
        t.Fatalf("Expected semantic version 1.5.2, got %s", v)
    }
}
EOF

    cd /home/user/test_env/go_app
    go mod init go_app

    chmod -R 777 /home/user
