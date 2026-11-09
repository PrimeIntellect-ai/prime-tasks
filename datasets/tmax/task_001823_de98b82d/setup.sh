#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/app/core
    mkdir -p /home/user/app/limiter

    cd /home/user/app
    go mod init app

    cat << 'EOF' > main.go
package main

import (
	"app/core"
	"fmt"
)

func main() {
	req := core.Request{ID: "req-1"}
	allowed := core.ProcessRequest(req)
	fmt.Printf("Request allowed: %v\n", allowed)
}
EOF

    cat << 'EOF' > core/core.go
package core

import "app/limiter"

type Request struct {
	ID string
}

func ProcessRequest(req Request) bool {
	l := limiter.NewLimiter()
	return l.Allow(req)
}
EOF

    cat << 'EOF' > limiter/limiter.go
package limiter

import "app/core"

type Limiter struct {
	// TODO: add concurrency primitives
}

func NewLimiter() *Limiter {
	return &Limiter{}
}

// Allow should only allow 5 requests total. Must be thread-safe.
func (l *Limiter) Allow(req core.Request) bool {
	// TODO: implement
	return true
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app
    chmod -R 777 /home/user
