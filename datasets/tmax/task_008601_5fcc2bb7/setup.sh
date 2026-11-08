#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/gateway
    cd /home/user/gateway
    go mod init gateway

    cat << 'EOF' > main.go
package main

import "fmt"

func main() {
	limiter := NewLimiter()
	fmt.Println("Gateway started with limiter:", limiter)
}
EOF

    cat << 'EOF' > limiter_fast.go
//go:build fast
// +build fast

package main

import "net/http"

type FastLimiter struct{}

func NewLimiter() *FastLimiter {
	return &FastLimiter{}
}

func (l *FastLimiter) Allow(req *http.Request) bool {
	// Hardware optimized stub
	return true
}
EOF

    cat << 'EOF' > limiter_fallback.go
//go:build fallback
// +build fallback

package main

import (
	"net/http"
)

type FallbackLimiter struct{}

func NewLimiter() *FallbackLimiter {
	return &FallbackLimiter{}
}

func (l *FallbackLimiter) Allow(req *http.Request) bool {
	// BUG: Unbuffered channel blocks the goroutine if it returns early via context cancellation
	done := make(chan bool) 

	go func() {
		// Simulate request validation
		if req.Header.Get("X-App-Config") == "" {
			done <- false
			return
		}
		done <- true
	}()

	select {
	case res := <-done:
		return res
	case <-req.Context().Done():
		// Context cancelled, early return, leaking the goroutine above because `done` has no readers
		return false
	}
}
EOF

    cat << 'EOF' > limiter_test.go
package main

import (
	"context"
	"net/http"
	"runtime"
	"testing"
	"time"
)

func TestLimiter_Concurrency(t *testing.T) {
	limiter := NewLimiter()

	// Wait a moment for any background system goroutines to settle
	time.Sleep(10 * time.Millisecond)
	startGoroutines := runtime.NumGoroutine()

	for i := 0; i < 100; i++ {
		ctx, cancel := context.WithCancel(context.Background())
		req, _ := http.NewRequestWithContext(ctx, "GET", "/", nil)
		cancel() // Instantly cancel context to trigger the early return path
		limiter.Allow(req)
	}

	time.Sleep(100 * time.Millisecond)
	endGoroutines := runtime.NumGoroutine()

	if endGoroutines > startGoroutines + 10 {
		t.Fatalf("goroutine leak detected: started with %d, ended with %d", startGoroutines, endGoroutines)
	}
}

func TestLimiter_Validation(t *testing.T) {
	limiter := NewLimiter()

	req, _ := http.NewRequest("GET", "/", nil)
	// FIX REQUIRED: set X-App-Config header to valid-config

	allowed := limiter.Allow(req)
	if !allowed {
		t.Fatalf("Request validation failed: expected true, got false. Make sure the X-App-Config header is set in the test fixture.")
	}
}
EOF

    chown -R user:user /home/user/gateway
    chmod -R 777 /home/user
