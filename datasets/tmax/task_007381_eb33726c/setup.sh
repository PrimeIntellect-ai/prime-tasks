#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl tar build-essential
    pip3 install pytest

    # Install Go 1.22
    wget https://go.dev/dl/go1.22.5.linux-amd64.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf go1.22.5.linux-amd64.tar.gz
    rm go1.22.5.linux-amd64.tar.gz
    export PATH=/usr/local/go/bin:$PATH

    # Initialize directories
    mkdir -p /home/user/workspace /home/user/release
    cd /home/user/workspace

    # Initialize go module
    go mod init math-api

    # Create buggy main.go
    cat << 'EOF' > /home/user/workspace/main.go
package main

import (
	"fmt"
	"net/http"
	"strconv"
)

// GCD computes the Greatest Common Divisor of a and b.
// BUG: It currently doesn't handle negative numbers correctly, 
// causing property tests to fail.
func GCD(a, b int64) int64 {
	for b != 0 {
		t := b
		b = a % b
		a = t
	}
	return a
}

func gcdHandler(w http.ResponseWriter, r *http.Request) {
	aStr := r.PathValue("a")
	bStr := r.PathValue("b")

	a, err1 := strconv.ParseInt(aStr, 10, 64)
	b, err2 := strconv.ParseInt(bStr, 10, 64)

	if err1 != nil || err2 != nil {
		http.Error(w, "Invalid parameters", http.StatusBadRequest)
		return
	}

	result := GCD(a, b)
	fmt.Fprintf(w, "%d", result)
}

func main() {
	mux := http.NewServeMux()

	// BUG: The route pattern is incorrect for Go 1.22 path values
	mux.HandleFunc("/gcd", gcdHandler)

	http.ListenAndServe(":8080", mux)
}
EOF

    # Create main_test.go with property-based tests
    cat << 'EOF' > /home/user/workspace/main_test.go
package main

import (
	"testing"
	"testing/quick"
)

func TestGCDProperty(t *testing.T) {
	// Property: GCD(a, b) must always be non-negative
	nonNegativeProp := func(a, b int64) bool {
		return GCD(a, b) >= 0
	}
	if err := quick.Check(nonNegativeProp, nil); err != nil {
		t.Errorf("Non-negative property failed: %v", err)
	}

	// Property: GCD(a, b) divides both a and b without remainder
	dividesProp := func(a, b int64) bool {
		g := GCD(a, b)
		if g == 0 {
			return a == 0 && b == 0
		}
		return a%g == 0 && b%g == 0
	}
	if err := quick.Check(dividesProp, nil); err != nil {
		t.Errorf("Divides property failed: %v", err)
	}
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
