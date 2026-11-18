#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest aiohttp

    mkdir -p /app/vendored/goproxy-1.0
    cat << 'EOF' > /app/vendored/goproxy-1.0/main.go
package main

import (
	"io"
	"net/http"
	"sync/atomic"
)

var backends = []string{"http://localhost:8081", "http://localhost:8082"}
var counter uint64

type Job struct {
	w http.ResponseWriter
	r *http.Request
}

var jobs = make(chan Job)
var results = make(chan string)

func worker() {
	for job := range jobs {
		idx := atomic.AddUint64(&counter, 1) % 2
		url := backends[idx] + job.r.URL.Path + "?" + job.r.URL.RawQuery
		resp, err := http.Get(url)
		if err == nil {
			defer resp.Body.Close()
			io.ReadAll(resp.Body)
		}
		// Bug: writing to unbuffered channel without a reader causes deadlock
		results <- "done"
	}
}

func handler(w http.ResponseWriter, r *http.Request) {
	jobs <- Job{w, r}
	w.Write([]byte("ok"))
}

func main() {
	for i := 0; i < 10; i++ {
		go worker()
	}
	http.HandleFunc("/", handler)
	http.ListenAndServe(":8080", nil)
}
EOF

    mkdir -p /home/user/backend
    cat << 'EOF' > /home/user/backend/server.py
import sys
from aiohttp import web

async def handle(request):
    n = request.query.get('n', '1')
    # Dummy factorization for speed
    return web.Response(text=f"Factors of {n}")

app = web.Application()
app.add_routes([web.get('/factor', handle)])

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
    web.run_app(app, port=port)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
