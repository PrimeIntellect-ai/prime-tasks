#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go curl
    pip3 install pytest psutil requests

    mkdir -p /app/math-service

    cat << 'EOF' > /app/math-service/go.mod
module math-service

go 1.18
EOF

    cat << 'EOF' > /app/math-service/main.go
package main

import (
	"fmt"
	"log"
	"net/http"
	"strconv"
)

func main() {
	http.HandleFunc("/factorize", func(w http.ResponseWriter, r *http.Request) {
		nStr := r.URL.Query().Get("n")
		if nStr == "" {
			nStr = "100"
		}
		n, err := strconv.Atoi(nStr)
		if err != nil {
			http.Error(w, "Invalid number", http.StatusBadRequest)
			return
		}
		factors := Process(n)
		fmt.Fprintf(w, "%v", factors)
	})
	log.Println("Starting server on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

    cat << 'EOF' > /app/math-service/processor.go
package main

import "fmt"

var cache = make(map[string][]int)

func Process(n int) []int {
	key := fmt.Sprintf("factorize_%d", n)
	if val, ok := cache[key]; ok {
		return val
	}

	factors := []int{}
	temp := n
	for i := 2; i <= temp; i++ {
		for temp%i == 0 {
			factors = append(factors, i)
			temp /= i
		}
	}

	cache[key] = factors
	return factors
}
EOF

    cat << 'EOF' > /app/math-service/Makefile
build:
	go build -ldflags="-s -w" -o bin/math-service cmd/math-service/main.go
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app/math-service
    chmod -R 777 /home/user
