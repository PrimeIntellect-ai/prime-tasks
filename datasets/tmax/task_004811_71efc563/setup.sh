#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang cargo build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_source

    cat << 'EOF' > /home/user/raw_source/analyzer.rs
use std::os::raw::c_char;
use std::ffi::CStr;

fn check_sqli_internal(payload: &str) -> bool {
    let lower = payload.to_lowercase();
    lower.contains("union select") || lower.contains("1=1") || lower.contains("drop table")
}

#[no_mangle]
pub extern "C" fn analyze_payload(c_str: *const c_char) -> bool {
    if c_str.is_null() { return false; }
    let c_str = unsafe { CStr::from_ptr(c_str) };
    match c_str.to_str() {
        Ok(s) => check_sqli_internal(s),
        Err(_) => false,
    }
}
EOF

    cat << 'EOF' > /home/user/raw_source/main.go
package main

/*
#cgo LDFLAGS: -L../rust_lib/target/release -lrust_lib -lm -ldl
#include <stdlib.h>
#include <stdbool.h>

extern bool analyze_payload(const char* c_str);
*/
import "C"
import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"sync"
	"unsafe"
)

type LogEntry struct {
	ID      int    `json:"id"`
	Payload string `json:"payload"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: scanner <logfile>")
		os.Exit(1)
	}

	file, err := os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer file.Close()

	jobs := make(chan string, 100)
	results := make(chan bool, 100)

	var wg sync.WaitGroup
	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for payload := range jobs {
				cStr := C.CString(payload)
				isSqli := C.analyze_payload(cStr)
				C.free(unsafe.Pointer(cStr))
				if isSqli {
					results <- true
				} else {
					results <- false
				}
			}
		}()
	}

	go func() {
		scanner := bufio.NewScanner(file)
		for scanner.Scan() {
			var entry LogEntry
			if err := json.Unmarshal(scanner.Bytes(), &entry); err == nil {
				jobs <- entry.Payload
			}
		}
		close(jobs)
		wg.Wait()
		close(results)
	}()

	sqliCount := 0
	for res := range results {
		if res {
			sqliCount++
		}
	}
	fmt.Printf("Detected %d SQLi attempts\n", sqliCount)
}
EOF

    cat << 'EOF' > /home/user/raw_source/logs.jsonl
{"id": 1, "payload": "hello world"}
{"id": 2, "payload": "admin' OR 1=1 --"}
{"id": 3, "payload": "user: john"}
{"id": 4, "payload": "UNION SELECT username, password FROM users"}
{"id": 5, "payload": "just a normal payload"}
{"id": 6, "payload": "DROP TABLE students;"}
EOF

    chmod -R 777 /home/user
