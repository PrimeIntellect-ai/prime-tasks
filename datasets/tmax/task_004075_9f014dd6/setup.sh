#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app /home/user/data

    cat << 'EOF' > /tmp/normalizer.go
package main
import (
	"bufio"
	"fmt"
	"os"
	"unicode"
)
func main() {
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		text := scanner.Text()
		var res []rune
		for _, r := range text {
			if unicode.IsLetter(r) || unicode.IsNumber(r) {
				res = append(res, unicode.ToLower(r))
			}
		}
		fmt.Println(string(res))
	}
}
EOF
    go build -ldflags="-s -w" -o /app/normalizer /tmp/normalizer.go
    rm /tmp/normalizer.go

    cat << 'EOF' > /home/user/data/sample_logs.jsonl
{"id": "1", "lang": "en", "message": "Hello World!"}
{"id": "2", "lang": "en", "message": "hello, world."}
{"id": "3", "lang": "ja", "message": "こんにちは世界"}
{"id": "4", "lang": "ja", "message": "こんにちは、世界！"}
{"id": "5", "lang": "es", "message": "¡Hola Mundo!"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
