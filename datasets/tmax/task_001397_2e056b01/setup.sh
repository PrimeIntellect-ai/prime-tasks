#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/leaky_encoder.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type Log struct {
	Stage string `json:"stage"`
	Text  string `json:"text"`
}

func main() {
	dict := make(map[string]int)
	counter := 1
	scanner := bufio.NewScanner(os.Stdin)

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}
		var log Log
		if err := json.Unmarshal([]byte(line), &log); err != nil {
			fmt.Println("ERROR")
			continue
		}

		words := strings.Split(log.Text, " ")
		var out []string
		for _, w := range words {
			if w == "" {
				continue
			}
			if id, exists := dict[w]; exists {
				out = append(out, fmt.Sprintf("%d", id))
			} else {
				dict[w] = counter
				out = append(out, fmt.Sprintf("%d", counter))
				counter++
			}
		}
		fmt.Println(strings.Join(out, " "))
	}
}
EOF
    go build -ldflags="-s -w" -o /app/leaky_encoder /tmp/leaky_encoder.go
    rm /tmp/leaky_encoder.go
    chmod +x /app/leaky_encoder

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
