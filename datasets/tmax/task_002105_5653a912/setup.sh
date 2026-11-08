#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /app/vendored_service
    cat << 'EOF' > /app/vendored_service/main.go
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"runtime"
	"time"
)

type Payload struct {
	Data string `json:"data"`
}

func main() {
	http.HandleFunc("/process", handleProcess)
	http.HandleFunc("/goroutines", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "%d", runtime.NumGoroutine())
	})
	http.ListenAndServe("127.0.0.1:8080", nil)
}

func handleProcess(w http.ResponseWriter, r *http.Request) {
	dec := json.NewDecoder(r.Body)
	for {
		var p Payload
		err := dec.Decode(&p)
		if err == io.EOF {
			break
		}
		if err != nil {
			// Bug 1: infinite loop on corrupted JSON input
			continue
		}
	}

	ch := make(chan string) // Bug 2: unbuffered channel
	go func() {
		time.Sleep(200 * time.Millisecond)
		ch <- "processed" // blocks forever if context is cancelled
	}()

	select {
	case res := <-ch:
		w.Write([]byte(res))
	case <-r.Context().Done():
		// request cancelled, but goroutine is left hanging
		return
	}
}
EOF

    cd /app/vendored_service && go mod init vendored_service

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
