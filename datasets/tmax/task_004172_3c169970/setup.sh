#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang espeak
    pip3 install --default-timeout=100 pytest

    mkdir -p /app/corpus/clean /app/corpus/evil /app/proxy /app/backend

    # Generate auth_token.wav
    espeak -w /app/auth_token.wav "blackberry"

    # Generate clean corpus
    for i in $(seq 1 50); do
        echo "{\"username\": \"user${i}\", \"age\": 25}" > /app/corpus/clean/clean_${i}.txt
    done

    # Generate evil corpus
    for i in $(seq 1 50); do
        echo "' OR 1=1 -- alert(1)" > /app/corpus/evil/evil_${i}.txt
    done

    # Create proxy files
    cat << 'EOF' > /app/proxy/main.c
int main() {
    printf("Starting proxy...\n")
    return 0;
}
EOF

    cat << 'EOF' > /app/proxy/proxy.c
void start_proxy() {
    int x = "string";
}
EOF

    cat << 'EOF' > /app/proxy/filter.c
int validate_payload(const char* payload) { return 0; }
EOF

    cat << 'EOF' > /app/proxy/filter.h
int validate_payload(const char* payload);
EOF

    # Create backend files
    cat << 'EOF' > /app/backend/main.go
package main
import "fmt"
func main() {
    unused := 1
    fmt.Println("Server started")
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
