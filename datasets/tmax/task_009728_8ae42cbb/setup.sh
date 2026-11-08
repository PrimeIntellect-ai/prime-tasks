#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang cargo patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/system_check/rust_app/src

    cat << 'EOF' > /home/user/system_check/libcore.c
#include <stdlib.h>
long process_data(long input) {
    long* ptr = malloc(sizeof(long)); // Fixed in patch to free it
    *ptr = input * 2;
    long result = *ptr;
    return result;
}
EOF

    cat << 'EOF' > /home/user/system_check/rust_app/Cargo.toml
[package]
name = "rust_app"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /home/user/system_check/rust_app/src/main.rs
extern "C" {
    fn process_data(input: i32) -> i32;
}

fn main() {
    unsafe {
        let res = process_data(21);
        println!("Result: {}", res);
    }
}
EOF

    cat << 'EOF' > /home/user/system_check/abi_update.patch
--- rust_app/src/main.rs
+++ rust_app/src/main.rs
@@ -1,10 +1,10 @@
 extern "C" {
-    fn process_data(input: i32) -> i32;
+    fn process_data(input: i64) -> i64;
 }

 fn main() {
     unsafe {
-        let res = process_data(21);
+        let res = process_data(21i64);
         println!("Result: {}", res);
     }
 }
--- libcore.c
+++ libcore.c
@@ -3,6 +3,7 @@
     long* ptr = malloc(sizeof(long)); // Fixed in patch to free it
     *ptr = input * 2;
     long result = *ptr;
+    free(ptr);
     return result;
 }
EOF

    cat << 'EOF' > /home/user/system_check/stress_test.go
package main

import (
	"fmt"
	"os/exec"
	"sync"
)

func main() {
	var wg sync.WaitGroup
	results := make(chan string, 5)

	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			cmd := exec.Command("./rust_app/target/debug/rust_app")
			out, err := cmd.Output()
			if err != nil {
				results <- fmt.Sprintf("Error %d", id)
				return
			}
			results <- string(out)
		}(i)
	}

	// BUG: missing goroutine to wait and close channel

	success := true
	for res := range results {
		if res == "" {
			success = false
		}
	}

	if success {
		fmt.Println("All workers completed successfully")
	}
}
EOF

    chmod -R 777 /home/user
