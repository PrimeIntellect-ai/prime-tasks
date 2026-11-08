#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc build-essential patch
    pip3 install pytest

    mkdir -p /home/user/release_prep/c_src
    mkdir -p /home/user/release_prep/rust_wrapper/src

    # Create the C header
    cat << 'EOF' > /home/user/release_prep/c_src/route_parser.h
#ifndef ROUTE_PARSER_H
#define ROUTE_PARSER_H

int extract_item_id(const char* url, char* out_buf, int out_len);

#endif
EOF

    # Create the initial (buggy) C source
    cat << 'EOF' > /home/user/release_prep/c_src/route_parser.c
#include "route_parser.h"
#include <string.h>

int extract_item_id(const char* url, char* out_buf, int out_len) {
    const char* prefix = "/api/item/";
    if (strncmp(url, prefix, 10) != 0) {
        return -1;
    }
    const char* id_start = url + 10;
    // BUG: doesn't check out_len properly, uses strcpy
    strcpy(out_buf, id_start);
    return 0;
}
EOF

    # Create the patch file
    cat << 'EOF' > /home/user/release_prep/security_fix.patch
--- c_src/route_parser.c
+++ c_src/route_parser.c
@@ -8,6 +8,10 @@
         return -1;
     }
     const char* id_start = url + 10;
-    // BUG: doesn't check out_len properly, uses strcpy
-    strcpy(out_buf, id_start);
+    int id_len = strlen(id_start);
+    if (id_len >= out_len) {
+        return -1;
+    }
+    strncpy(out_buf, id_start, out_len);
+    out_buf[id_len] = '\0';
     return 0;
 }
EOF

    # Setup Rust project
    cat << 'EOF' > /home/user/release_prep/rust_wrapper/Cargo.toml
[package]
name = "rust_wrapper"
version = "0.1.0"
edition = "2021"

[dependencies]
libc = "0.2"

[dev-dependencies]
proptest = "1.0"

[build-dependencies]
cc = "1.0"
EOF

    cat << 'EOF' > /home/user/release_prep/rust_wrapper/build.rs
fn main() {
    cc::Build::new()
        .file("../c_src/route_parser.c")
        .compile("route_parser");
    println!("cargo:rerun-if-changed=../c_src/route_parser.c");
}
EOF

    cat << 'EOF' > /home/user/release_prep/rust_wrapper/src/lib.rs
// FFI bindings and tests go here
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
