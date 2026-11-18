#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        rustc \
        cargo \
        golang \
        ffmpeg \
        espeak \
        patch

    pip3 install pytest

    mkdir -p /app/bc-patcher/src

    # Create Cargo.toml
    cat << 'EOF' > /app/bc-patcher/Cargo.toml
[package]
name = "bc-patcher"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    # Create Rust file with borrow checker error
    cat << 'EOF' > /app/bc-patcher/src/main.rs
use std::process::Command;
use std::env;

fn get_command_name<'a>() -> &'a str {
    let cmd = String::from("patch");
    &cmd // ERROR: returns a reference to a local variable
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 4 {
        eprintln!("Usage: {} <input> <patch> <output>", args[0]);
        std::process::exit(1);
    }
    let cmd_name = get_command_name();
    Command::new(cmd_name)
        .arg(&args[1])
        .arg("-i")
        .arg(&args[2])
        .arg("-o")
        .arg(&args[3])
        .status()
        .unwrap();
}
EOF

    # Create rules.bc
    cat << 'EOF' > /app/rules.bc
LOAD
LOAD
ADD
SMOOTH
OUT
EOF

    # Create hotfix.patch
    cat << 'EOF' > /app/hotfix.patch
--- rules.bc
+++ rules.bc
@@ -1,5 +1,6 @@
 LOAD
-LOAD
-ADD
 SMOOTH
+LOAD
+SMOOTH
+ADD
 OUT
EOF

    # Generate voicemail.wav
    espeak -w /app/voicemail.wav "Update the telemetry processor. Set the smoothing alpha to zero point seven five and the bias to fifteen."

    # Create oracle in Go
    cat << 'EOF' > /tmp/oracle.go
package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		return
	}
	bcData, _ := os.ReadFile(os.Args[1])
	instructions := strings.Split(strings.TrimSpace(string(bcData)), "\n")

	scanner := bufio.NewScanner(os.Stdin)
	stack := []int{}
	prevSmooth := 0.0
	alpha := 0.75
	bias := 15.0

	for _, inst := range instructions {
		inst = strings.TrimSpace(inst)
		switch inst {
		case "LOAD":
			if scanner.Scan() {
				val, _ := strconv.Atoi(strings.TrimSpace(scanner.Text()))
				stack = append(stack, val)
			}
		case "ADD":
			if len(stack) >= 2 {
				a := stack[len(stack)-2]
				b := stack[len(stack)-1]
				stack = stack[:len(stack)-2]
				stack = append(stack, a+b)
			}
		case "MUL":
			if len(stack) >= 2 {
				a := stack[len(stack)-2]
				b := stack[len(stack)-1]
				stack = stack[:len(stack)-2]
				stack = append(stack, a*b)
			}
		case "SMOOTH":
			if len(stack) >= 1 {
				val := stack[len(stack)-1]
				stack = stack[:len(stack)-1]
				curr := alpha*float64(val) + (1.0-alpha)*prevSmooth + bias
				prevSmooth = curr
				stack = append(stack, int(math.Floor(curr)))
			}
		case "OUT":
			if len(stack) >= 1 {
				val := stack[len(stack)-1]
				stack = stack[:len(stack)-1]
				fmt.Println(val)
			}
		}
	}
}
EOF

    go build -o /app/oracle_bin /tmp/oracle.go
    chmod +x /app/oracle_bin
    rm /tmp/oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
