#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git golang python3-scapy tshark curl sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/collatz-service
    cd /home/user/collatz-service

    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > server.go
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
)

var (
	cache = make(map[int][]int)
	mu    sync.Mutex
)

type Request struct {
	Number int `json:"number"`
}

func collatz(n int) []int {
	var seq []int
	// BUG: If n <= 0, this loops infinitely and consumes all memory
	for n != 1 {
		seq = append(seq, n)
		if n%2 == 0 {
			n = n / 2
		} else {
			n = 3*n + 1
		}
	}
	seq = append(seq, 1)
	return seq
}

func calculateHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req Request
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	mu.Lock()
	if val, ok := cache[req.Number]; ok {
		mu.Unlock()
		json.NewEncoder(w).Encode(val)
		return
	}
	mu.Unlock()

	seq := collatz(req.Number)

	mu.Lock()
	cache[req.Number] = seq
	mu.Unlock()

	json.NewEncoder(w).Encode(seq)
}

func main() {
	http.HandleFunc("/calculate", calculateHandler)
	fmt.Println("Starting server on :8080")
	http.ListenAndServe(":8080", nil)
}
EOF

    git add server.go
    git commit -m "Initial commit with collatz server"

    git rm server.go
    git commit -m "Remove server.go"
    git reset --hard HEAD~1
    rm -f server.go

    cd /home/user
    cat << 'EOF' > generate_pcap.py
from scapy.all import *

def make_http_post(port, payload):
    ip = IP(dst="127.0.0.1", src="127.0.0.1")
    tcp = TCP(sport=12345, dport=port, flags="PA", seq=1, ack=1)
    http_req = f"POST /calculate HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nContent-Type: application/json\r\nContent-Length: {len(payload)}\r\n\r\n{payload}"
    return ip/tcp/Raw(load=http_req)

packets = []
packets.append(make_http_post(8080, '{"number": 10}'))
packets.append(make_http_post(8080, '{"number": 27}'))
packets.append(make_http_post(8080, '{"number": 15}'))
packets.append(make_http_post(8080, '{"number": 0}'))

wrpcap("/home/user/traffic.pcap", packets)
EOF

    python3 generate_pcap.py
    rm generate_pcap.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
