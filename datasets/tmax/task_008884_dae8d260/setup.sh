#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc libc6-dev musl-tools curl file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/waf-proxy

    cat << 'EOF' > /home/user/waf-proxy/sanitizer.h
#ifndef SANITIZER_H
#define SANITIZER_H

void sanitize_header(const char* input, char* output, int max_len);

#endif
EOF

    cat << 'EOF' > /home/user/waf-proxy/sanitizer.c
#include "sanitizer.h"

void sanitize_header(const char* input, char* output, int max_len) {
    int i = 0;
    // VULNERABILITY: ignores max_len, causing buffer overflow
    while(input[i] != '\0') {
        output[i] = input[i];
        i++;
    }
    output[i] = '\0';
}
EOF

    cat << 'EOF' > /home/user/waf-proxy/main.go
package main

// #include <stdlib.h>
// #include "sanitizer.h"
import "C"
import (
	"fmt"
	"io/ioutil"
	"net/http"
	"net/http/httputil"
	"net/url"
	"unsafe"
)

func main() {
	target, _ := url.Parse("http://127.0.0.1:9090")
	proxy := httputil.NewSingleHostReverseProxy(target)

	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)

		val := req.Header.Get("X-Custom-User")
		if val != "" {
			inputC := C.CString(val)
			defer C.free(unsafe.Pointer(inputC))

			// Allocate exactly 64 bytes
			outputC := (*C.char)(C.malloc(64))
			defer C.free(unsafe.Pointer(outputC))

			C.sanitize_header(inputC, outputC, 64)
			req.Header.Set("X-Custom-User", C.GoString(outputC))
		}
	}

	http.ListenAndServe("127.0.0.1:8080", proxy)
}
EOF

    cd /home/user/waf-proxy
    go mod init waf-proxy

    chmod -R 777 /home/user
