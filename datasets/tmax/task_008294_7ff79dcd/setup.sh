#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc
    pip3 install pytest

    mkdir -p /home/user/analyzer
    cd /home/user/analyzer

    cat << 'EOF' > parser.h
#ifndef PARSER_H
#define PARSER_H
void parse_uri(const char *req, char *out);
#endif
EOF

    cat << 'EOF' > parser.c
#include <stdio.h>
#include <string.h>
#include "parser.h"

void parse_uri(const char *req, char *out) {
    char buf[64]; // Vulnerable buffer
    // Vulnerability: Unbounded copy
    sscanf(req, "GET %s HTTP", buf);
    strcpy(out, buf);
}
EOF

    cat << 'EOF' > main.go
package main

/*
#cgo CFLAGS: -I.
#cgo LDFLAGS: -L.
#include <stdlib.h>
#include "parser.h"
*/
import "C"
import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"sync"
	"unsafe"
)

func extractURI(req string) string {
	creq := C.CString(req)
	defer C.free(unsafe.Pointer(creq))

	cout := (*C.char)(C.malloc(1024))
	defer C.free(unsafe.Pointer(cout))

	C.parse_uri(creq, cout)
	return C.GoString(cout)
}

func main() {
	file, err := os.Open("requests.log")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	var wg sync.WaitGroup
	scanner := bufio.NewScanner(file)

	var malicious []string

	for scanner.Scan() {
		line := scanner.Text()
		wg.Add(1)
		go func(l string) {
			defer wg.Done()
			uri := extractURI(l)
			if strings.Contains(uri, "UNION") || strings.Contains(uri, "SELECT") {
				// BUG: Data race here
				malicious = append(malicious, uri)
			}
		}(line)
	}
	wg.Wait()

	for _, m := range malicious {
		fmt.Println(m)
	}
}
EOF

    cat << 'EOF' > requests.log
GET /index.html HTTP/1.1
GET /about.php HTTP/1.1
GET /login.php?user=admin'UNION+SELECT+1,2,3-- HTTP/1.1
GET /api/data?id=4 HTTP/1.1
GET /products?cat=shoes HTTP/1.1
GET /search?q=UNION+SELECT+password+FROM+users HTTP/1.1
GET /aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaUNIONSELECT HTTP/1.1
GET /login.php?user=admin'UNION+SELECT+1,2,3-- HTTP/1.1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
