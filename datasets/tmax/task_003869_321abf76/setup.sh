#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/project/solver
    mkdir -p /home/user/project/utils

    cat << 'EOF' > /home/user/project/go.mod
module project

go 1.18
EOF

    cat << 'EOF' > /home/user/project/main.go
package main

import (
	"fmt"
	"os"
	"strconv"
	"project/solver"
)

func main() {
	if len(os.Args) < 2 {
		return
	}
	target, _ := strconv.Atoi(os.Args[1])
	weights := []int{2, 3, 5, 7, 11, 13, 17, 19}
	res := solver.FindSubset(weights, target)
	fmt.Println(res)
}
EOF

    cat << 'EOF' > /home/user/project/solver/solver.go
package solver

import (
	"project/utils"
)

func FindSubset(weights []int, target int) bool {
	if target == 0 {
		return true
	}
	if target < 0 || len(weights) == 0 {
		return false
	}
	// Try including the first weight
	if FindSubset(weights[1:], target-weights[0]) {
		return true
	}
	// Try excluding it
	return utils.HelperFind(weights[1:], target)
}
EOF

    cat << 'EOF' > /home/user/project/utils/utils.go
package utils

import "project/solver"

func HelperFind(weights []int, target int) bool {
	return solver.FindSubset(weights, target)
}
EOF

    cat << 'EOF' > /home/user/project/e2e_test.py
import subprocess
import sys
import os

def run_test(target, expected):
    app_path = os.path.join(os.path.dirname(__file__), "app")
    res = subprocess.run([app_path, str(target)], capture_output=True, text=True)
    out = res.stdout.strip()
    return out == str(expected).lower()

if __name__ == "__main__":
    tests = [
        (24, True),   # e.g., 17 + 7
        (4, False),   # No combination sums to 4
        (10, True),   # 7 + 3
        (100, False)
    ]

    all_passed = True
    for t, exp in tests:
        if not run_test(t, exp):
            all_passed = False
            break

    if all_passed:
        print("E2E TESTS PASSED")
    else:
        print("E2E TESTS FAILED")
        sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
