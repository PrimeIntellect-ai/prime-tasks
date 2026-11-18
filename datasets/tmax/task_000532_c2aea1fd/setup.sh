#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go make curl
    pip3 install pytest

    mkdir -p /app/safe-router-1.1.0
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    cat << 'EOF' > /app/safe-router-1.1.0/Makefile
build:
    go build -o safe-router .

clean:
    rm -f safe-router
EOF

    cat << 'EOF' > /app/safe-router-1.1.0/main.go
package main

import (
	"bufio"
	"bytes"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
)

func main() {
	corpusPtr := flag.String("corpus", "", "Path to corpus directory")
	flag.Parse()

	if len(flag.Args()) > 0 && flag.Args()[0] == "verify" {
		if *corpusPtr == "" {
			log.Fatal("Must provide --corpus")
		}
		verifyCorpus(*corpusPtr)
		return
	}

	socket := "/var/run/broken.sock"
	fmt.Println("Connecting to", socket)
}

func verifyCorpus(corpusPath string) {
	evilDir := filepath.Join(corpusPath, "evil")
	cleanDir := filepath.Join(corpusPath, "clean")

	evilFiles, _ := ioutil.ReadDir(evilDir)
	for _, f := range evilFiles {
		req := parseReq(filepath.Join(evilDir, f.Name()))
		if !IsMalicious(req) {
			log.Fatalf("Failed to flag evil request: %s", f.Name())
			os.Exit(1)
		}
	}

	cleanFiles, _ := ioutil.ReadDir(cleanDir)
	for _, f := range cleanFiles {
		req := parseReq(filepath.Join(cleanDir, f.Name()))
		if IsMalicious(req) {
			log.Fatalf("Incorrectly flagged clean request: %s", f.Name())
			os.Exit(1)
		}
	}
	fmt.Println("Corpus verification passed")
}

func parseReq(path string) *http.Request {
	data, _ := ioutil.ReadFile(path)
	req, _ := http.ReadRequest(bufio.NewReader(bytes.NewReader(data)))
	if req == nil {
		req, _ = http.NewRequest("GET", "/", nil)
	}
	if req != nil && req.URL != nil {
	    // Ensure the raw path is available for testing
	    req.URL.RawPath = req.URL.EscapedPath()
	}
	return req
}
EOF

    cat << 'EOF' > /app/safe-router-1.1.0/filter.go
package main

import "net/http"

func IsMalicious(req *http.Request) bool {
	return false
}
EOF

    cat << 'EOF' > /app/safe-router-1.1.0/go.mod
module safe-router

go 1.18
EOF

    cat << 'EOF' > /app/corpus/evil/1.http
GET /../../../etc/passwd HTTP/1.1
Host: example.com

EOF

    cat << 'EOF' > /app/corpus/evil/2.http
GET / HTTP/1.1
Host: example.com
X-Forwarded-Host: attacker.com

EOF

    cat << 'EOF' > /app/corpus/evil/3.http
GET / HTTP/1.1
Host: example.com
User-Agent: sqlmap/1.0

EOF

    cat << 'EOF' > /app/corpus/clean/1.http
GET /index.html HTTP/1.1
Host: example.com
User-Agent: Mozilla/5.0

EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
