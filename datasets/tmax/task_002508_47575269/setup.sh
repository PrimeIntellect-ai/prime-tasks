#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc
    pip3 install pytest

    mkdir -p /home/user/workspace/go_calc/ops
    mkdir -p /home/user/workspace/go_calc/util

    cd /home/user/workspace/go_calc
    go mod init go_calc

    cat << 'EOF' > main.go
package main

import "C"
import "go_calc/ops"

//export Compute
func Compute(a C.int, b C.int, op C.int) C.int {
	resChan := make(chan int)
	go func() {
		resChan <- ops.Execute(int(a), int(b), int(op))
	}()
	return C.int(<-resChan)
}

func main() {}
EOF

    cat << 'EOF' > ops/ops.go
package ops

import "go_calc/util"

func Execute(a, b, op int) int {
	if op == 1 {
		return a + b
	} else if op == 2 {
		return a - b
	} else if op == 3 {
		return a * b
	}
	return util.DefaultVal()
}
EOF

    cat << 'EOF' > util/util.go
package util

import "go_calc/ops"

func DefaultVal() int {
	return 0
}

func UnusedRef() {
	ops.Execute(0, 0, 0)
}
EOF

    cd /home/user/workspace
    cat << 'EOF' > program.txt
PUSH 10
PUSH 5
ADD
PRINT
PUSH 20
PUSH 4
SUB
PRINT
PUSH 7
PUSH 6
MUL
PRINT
PUSH 3
PUSH 2
PUSH 4
MUL
ADD
PRINT
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
