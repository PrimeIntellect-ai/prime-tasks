#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go jq ruby curl git
    pip3 install pytest

    # Create directories
    mkdir -p /app/go-httpbin/cmd/httpbin
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /home/user

    # Create dummy go-httpbin
    cat << 'EOF' > /app/go-httpbin/go.mod
module github.com/example/go-httpbin

go 1.18
EOF

    cat << 'EOF' > /app/go-httpbin/cmd/httpbin/main.go
package main

import (
	"flag"
	"fmt"
	"log"
)

func main() {
	help := flag.Bool("h", false, "help")
	flag.Parse()
	if *help {
		fmt.Println("Usage instructions")
		return
	}
	// padding to line 42
	// 18
	// 19
	// 20
	// 21
	// 22
	// 23
	// 24
	// 25
	// 26
	// 27
	// 28
	// 29
	// 30
	// 31
	// 32
	// 33
	// 34
	// 35
	// 36
	// 37
	// 38
	// 39
	// 40
	// 41
	log.Fatalff("error")
}
EOF
    cp /app/go-httpbin/cmd/httpbin/main.go /app/go-httpbin/main.go

    # Create legacy Ruby script
    cat << 'EOF' > /home/user/legacy_filter.rb
#!/usr/bin/env ruby
require 'json'

begin
  payload = JSON.parse(STDIN.read)
  role = payload.dig('user', 'role')
  permissions = payload.dig('user', 'permissions') || []

  if role == 'admin' && permissions.include?('all') && !permissions.any? { |p| p.include?('<script>') }
    puts "ACCEPT"
    exit 0
  else
    puts "REJECT"
    exit 1
  end
rescue
  puts "REJECT"
  exit 1
end
EOF
    chmod +x /home/user/legacy_filter.rb

    # Create clean corpora
    for i in $(seq 1 20); do
        cat << 'EOF' > /app/corpora/clean/payload_${i}.json
{
  "user": {
    "role": "admin",
    "permissions": ["all", "read", "write"]
  }
}
EOF
    done

    # Create evil corpora
    for i in $(seq 1 20); do
        cat << 'EOF' > /app/corpora/evil/payload_${i}.json
{
  "user": {
    "role": "admin",
    "permissions": ["all", "<script>alert(1)</script>"]
  }
}
EOF
    done

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
