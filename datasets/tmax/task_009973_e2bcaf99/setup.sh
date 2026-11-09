#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip wget build-essential
pip3 install pytest

# Install Go 1.20
wget https://golang.org/dl/go1.20.14.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.20.14.linux-amd64.tar.gz
rm go1.20.14.linux-amd64.tar.gz
ln -s /usr/local/go/bin/go /usr/local/bin/go
ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt

mkdir -p /home/user/sec-app/lib

cat << 'EOF' > /home/user/sec-app/lib/token_check.h
#ifndef TOKEN_CHECK_H
#define TOKEN_CHECK_H
int validate_token(const char* token);
#endif
EOF

cat << 'EOF' > /home/user/sec-app/lib/token_check.c
#include "token_check.h"
int validate_token(const char* token) {
    return 1; // Dummy implementation
}
EOF

cat << 'EOF' > /home/user/sec-app/go.mod
module sec-app

go 1.20
EOF

cat << 'EOF' > /home/user/sec-app/middleware.go
package main

/*
#cgo CFLAGS: -I${SRCDIR}/lib
#cgo LDFLAGS: -L${SRCDIR}/lib -ltokencheck
#include <stdlib.h>
#include "token_check.h"
*/
import "C"
import (
	"net/http"
	"unsafe"
)

var requestCount int

func RateLimitMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestCount++
		// The limit should be 5
		if requestCount > 10 {
			http.Error(w, "Too Many Requests", http.StatusTooManyRequests)
			return
		}

		token := C.CString(r.Header.Get("X-Token"))
		defer C.free(unsafe.Pointer(token))

		if C.validate_token(token) == 0 {
			http.Error(w, "Invalid Token", http.StatusUnauthorized)
			return
		}

		next.ServeHTTP(w, r)
	})
}
EOF

cat << 'EOF' > /home/user/sec-app/middleware_test.go
package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRateLimit(t *testing.T) {
	requestCount = 0

	handler := RateLimitMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	for i := 1; i <= 6; i++ {
		req := httptest.NewRequest("GET", "http://example.com/foo", nil)
		req.Header.Set("X-Token", "secret")
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, req)

		if i <= 5 {
			if w.Result().StatusCode != http.StatusOK {
				t.Fatalf("Request %d failed, expected 200, got %d", i, w.Result().StatusCode)
			}
		} else {
			if w.Result().StatusCode != http.StatusTooManyRequests {
				t.Fatalf("Request %d failed, expected 429, got %d", i, w.Result().StatusCode)
			}
		}
	}
}
EOF

cat << 'EOF' > /home/user/sec-app/Makefile
all: test

lib/libtokencheck.so:
	gcc -shared -o lib/libtokencheck.so -fPIC lib/token_check.c

test: lib/libtokencheck.so
	go test -v ./... > test_results.log
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
