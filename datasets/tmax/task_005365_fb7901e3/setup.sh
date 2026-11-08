#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git golang tcpdump tshark
    pip3 install pytest scapy

    mkdir -p /app/vendored/go-cache-server
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Create corpus
    for i in $(seq 1 20); do
        printf "GET / HTTP/1.1\r\nHost: localhost\r\nX-Debug-Bypass: true\r\n\r\n" > /app/corpus/evil/$i.txt
        printf "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n" > /app/corpus/clean/$i.txt
    done

    # Create dummy pcap using scapy
    python3 -c "
from scapy.all import Ether, IP, TCP, Raw, wrpcap

pkts = []
for i in range(5):
    # Clean
    pkt = Ether()/IP(dst='127.0.0.1')/TCP(dport=80)/Raw(load='GET / HTTP/1.1\r\nHost: localhost\r\n\r\n')
    pkts.append(pkt)
    # Evil
    pkt = Ether()/IP(dst='127.0.0.1')/TCP(dport=80)/Raw(load='GET / HTTP/1.1\r\nHost: localhost\r\nX-Debug-Bypass: true\r\n\r\n')
    pkts.append(pkt)

wrpcap('/app/incident.pcap', pkts)
"

    # Set up git repo
    cd /app/vendored/go-cache-server
    git init
    git config user.email "admin@example.com"
    git config user.name "Admin"

    cat << 'EOF' > go.mod
module go-cache-server

go 1.18
EOF

    cat << 'EOF' > server.go
package main

import (
	"context"
	"net/http"
)

func HandleRequest(req *http.Request) {
	ctx, cancel := context.WithCancel(req.Context())
	defer cancel()
	_ = ctx
}
EOF
    git add go.mod server.go
    git commit -m "Initial commit"
    git tag v1.0.0

    # Commit 1
    echo "// comment 1" >> server.go
    git commit -am "Update 1"

    # Commit 2 (Bad commit)
    cat << 'EOF' > server.go
package main

import (
	"context"
	"net/http"
)

func HandleRequest(req *http.Request) {
	ctx, cancel := context.WithCancel(req.Context())
	if req.Header.Get("X-Debug-Bypass") != "" {
		// missing defer cancel()
	} else {
		defer cancel()
	}
	_ = ctx
}
EOF
    git commit -am "Introduce feature X"
    BAD_COMMIT=$(git rev-parse HEAD)

    # Commit 3
    echo "// comment 2" >> server.go
    git commit -am "Update 2"

    # Commit 4
    echo "// comment 3" >> server.go
    git commit -am "Update 3"

    useradd -m -s /bin/bash user || true
    echo "$BAD_COMMIT" > /home/user/bad_commit_hash_expected.txt

    chmod -R 777 /home/user
    chmod -R 777 /app
