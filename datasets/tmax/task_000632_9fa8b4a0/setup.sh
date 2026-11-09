#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang expect jq logrotate locales tzdata
    pip3 install pytest

    # Generate the required locale
    locale-gen ja_JP.UTF-8

    mkdir -p /home/user/service

    cat << 'EOF' > /home/user/service/daemon.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"
)

type Config struct {
	Port int `json:"port"`
}

func main() {
	if os.Getenv("TZ") != "Asia/Tokyo" {
		log.Fatal("Error: Timezone must be set to Asia/Tokyo")
	}
	if os.Getenv("LANG") != "ja_JP.UTF-8" {
		log.Fatal("Error: Locale must be ja_JP.UTF-8")
	}

	data, err := os.ReadFile("/home/user/service/config.json")
	if err != nil {
		log.Fatalf("Failed to read config: %v", err)
	}

	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		log.Fatalf("Invalid config JSON: %v", err)
	}

	if cfg.Port == 0 {
		log.Fatal("Port not specified in config")
	}

	fmt.Print("Enter initialization PIN: ")
	reader := bufio.NewReader(os.Stdin)
	pin, _ := reader.ReadString('\n')
	pin = strings.TrimSpace(pin)

	if pin != "8192" {
		log.Fatal("Invalid PIN")
	}

	f, err := os.OpenFile("/home/user/service/daemon.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()

	successMsg := fmt.Sprintf("Service started successfully on port %d\n", cfg.Port)
	f.WriteString(successMsg)
	fmt.Println(successMsg)

	// Simulate running
	time.Sleep(2 * time.Second)
	fmt.Println("Service shutting down cleanly.")
}
EOF

    cat << 'EOF' > /home/user/service/config.json
{
    "port": "eight-zero-eight-zero",
    "invalid_json": true,
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
