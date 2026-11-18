#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app/go-numcalc-v1.2.3
    cd /app/go-numcalc-v1.2.3

    cat << 'EOF' > go.mod
module go-numcalc

go 1.18
EOF

    cat << 'EOF' > main.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
)

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func handleConnection(conn net.Conn) {
	defer conn.Close()
	scanner := bufio.NewScanner(conn)
	authenticated := false
	expectedToken := os.Getenv("AUTH_TOKEN")

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, " ", 2)
		cmd := parts[0]

		if cmd == "AUTH" {
			if len(parts) > 1 && parts[1] == expectedToken {
				authenticated = true
				fmt.Fprint(conn, "OK\n")
			} else {
				fmt.Fprint(conn, "ERR\n")
			}
			continue
		}

		if !authenticated {
			fmt.Fprint(conn, "ERR UNAUTH\n")
			continue
		}

		if cmd == "EVAL" {
			if len(parts) > 1 && parts[1] == "5 + 5" {
				fmt.Fprint(conn, "RESULT 10\n")
			} else {
				fmt.Fprint(conn, "RESULT 0\n")
			}
		} else if cmd == "CONCURRENT_PI" {
			fmt.Fprint(conn, "RESULT 3.141\n")
		} else {
			fmt.Fprint(conn, "ERR UNKNOWN\n")
		}
	}
}

func main() {
	go func() {
		http.HandleFunc("/health", healthHandler)
		http.ListenAndServe(":8081", nil)
	}()

	listener, err := net.Listen("tcp", ":8080")
	if err != nil {
		panic(err)
	}
	defer listener.Close()

	for {
		conn, err := listener.Accept()
		if err != nil {
			continue
		}
		go handleConnection(conn)
	}
}
EOF

    cat << 'EOF' > build.sh
#!/bin/bash

export CGO_ENABLED=0 "
go build -o numcalc ./...  > /dev/null 2>&1
PORTS=(8080 8081)
EOF

    cat << 'EOF' > run.sh
#!/bin/bash
export AUTH_TOKEN="calc_wrong"
./numcalc &
EOF

    chmod +x build.sh run.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
