#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest

    wget https://go.dev/dl/go1.20.14.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.20.14.linux-amd64.tar.gz
    ln -s /usr/local/go/bin/go /usr/bin/go
    rm go1.20.14.linux-amd64.tar.gz

    mkdir -p /home/user/aggregator

    cat << 'EOF' > /home/user/aggregator/go.mod
module aggregator

go 1.20
EOF

    cat << 'EOF' > /home/user/aggregator/main.go
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
)

type Metric struct {
	Value float64 `json:"value"`
}

type Response struct {
	Variance float64 `json:"variance"`
}

var (
	mu     sync.Mutex
	count  int
	sum    float64
	sumSq  float64
)

func resetHandler(w http.ResponseWriter, r *http.Request) {
	mu.Lock()
	defer mu.Unlock()
	count = 0
	sum = 0
	sumSq = 0
	w.WriteHeader(http.StatusOK)
}

func metricHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var m Metric
	if err := json.NewDecoder(r.Body).Decode(&m); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	mu.Lock()
	defer mu.Unlock()

	count++
	sum += m.Value
	sumSq += m.Value * m.Value

	var variance float64
	if count > 1 {
		// Naive variance calculation (prone to catastrophic cancellation)
		mean := sum / float64(count)
		variance = (sumSq / float64(count)) - (mean * mean)
	}

	resp := Response{Variance: variance}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func main() {
	http.HandleFunc("/metric", metricHandler)
	http.HandleFunc("/reset", resetHandler)
	fmt.Println("Server listening on :8080")
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/dataset.json
[
  10.5, 12.1, 9.8, 11.2, 10.9, 10.1,
  10000000000.0, 10000000000.1, 10000000000.2,
  15.0, 14.5
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
