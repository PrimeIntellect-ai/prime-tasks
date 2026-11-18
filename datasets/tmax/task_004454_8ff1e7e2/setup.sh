#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        golang-go \
        git \
        strace \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    # Create the image with the token
    mkdir -p /app
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 36 -fill black -draw "text 20,60 'TR4CK_M3_N0W'" /app/auth_token.png

    # Setup the Go repository
    mkdir -p /home/user/repo
    cd /home/user/repo
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > go.mod
module kvstore

go 1.18
EOF

    cat << 'EOF' > main.go
package main

import (
	"net/http"
	"os"
)

func main() {
	token := os.Getenv("ADMIN_TOKEN")
	wal := NewWAL("data.wal")
	wal.Replay()

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	http.HandleFunc("/set", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer "+token {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		key := r.URL.Query().Get("key")
		val := r.URL.Query().Get("val")
		wal.Set(key, val)
		w.WriteHeader(http.StatusOK)
	})
	http.HandleFunc("/get", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer "+token {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		key := r.URL.Query().Get("key")
		val := wal.Get(key)
		w.Write([]byte(val))
	})
	http.ListenAndServe("127.0.0.1:9000", nil)
}
EOF

    cat << 'EOF' > wal.go
package main

import (
	"io"
	"os"
	"strings"
)

type WAL struct {
	filename string
	data     map[string]string
}

func NewWAL(filename string) *WAL {
	return &WAL{filename: filename, data: make(map[string]string)}
}

func (w *WAL) Replay() {
	f, err := os.Open(w.filename)
	if err != nil {
		return
	}
	defer f.Close()
	buf := make([]byte, 100)
	for {
		_, err := io.ReadFull(f, buf)
		if err == io.ErrUnexpectedEOF || err == io.EOF {
			break
		}
		parts := strings.SplitN(string(buf), "=", 2)
		if len(parts) == 2 {
			w.data[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		}
	}
}

func (w *WAL) Set(key, val string) {
	w.data[key] = val
	f, _ := os.OpenFile(w.filename, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if f != nil {
		defer f.Close()
		buf := make([]byte, 100)
		copy(buf, key+"="+val)
		f.Write(buf)
	}
}

func (w *WAL) Get(key string) string {
	return w.data[key]
}
EOF

    git add .
    git commit -m "Initial commit"

    # Create 100 commits
    for i in $(seq 1 100); do
        echo "// comment $i" >> main.go
        git commit -am "Commit $i"
    done

    # Introduce the bug
    sed -i 's/if err == io.ErrUnexpectedEOF || err == io.EOF {/if err == io.EOF {/' wal.go
    git commit -am "Refactor WAL read loop"

    # Create 99 more commits
    for i in $(seq 101 199); do
        echo "// comment $i" >> main.go
        git commit -am "Commit $i"
    done

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
