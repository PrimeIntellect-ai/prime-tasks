#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go make
    pip3 install pytest

    # Create directories
    mkdir -p /app/net-sniff-processor-v1.2.0
    mkdir -p /app/tests/corpus/clean
    mkdir -p /app/tests/corpus/evil

    # Create /app/net-sniff-processor-v1.2.0/main.go
    cat << 'EOF' > /app/net-sniff-processor-v1.2.0/main.go
package main
import "fmt"
func main() { fmt.Println("Sniffing...") }
EOF

    # Create /app/net-sniff-processor-v1.2.0/Makefile
    cat << 'EOF' > /app/net-sniff-processor-v1.2.0/Makefile
build:
	go build -mod=readonly -o net-sniff main.go
EOF

    # Create corpus files
    cat << 'EOF' > /app/tests/corpus/clean/1.txt
--source-ip=192.168.1.1
--dest-ip=10.0.0.5
--payload=GET /index.html HTTP/1.1
EOF

    cat << 'EOF' > /app/tests/corpus/evil/1.txt
--source-ip=10.0.0.2
--dest-ip=192.168.1.100
--payload=POST /login HTTP/1.1 PASSWORD=supersecretAKIA1234567890123456
EOF

    cat << 'EOF' > /app/tests/corpus/evil/2.txt
--metadata=user-auth
--token=AKIAABCDEFGHIJKLMNOP
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
