#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app/analytics-daemon-1.2.3
    cat << 'EOF' > /app/analytics-daemon-1.2.3/main.go
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"sync"
)

type Tracker struct {
	mu    sync.Mutex
	sum   float64
	count int
}

func (t *Tracker) Record(val float64) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.sum += val
	t.count++
}

func (t *Tracker) Stats() (float64, int) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.count == 0 {
		return 0, 0
	}
	return t.sum / float64(t.count), t.count
}

func main() {
	tracker := &Tracker{}

	http.HandleFunc("/submit", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		valStr := r.URL.Query().Get("value")
		val, err := strconv.ParseFloat(valStr, 64)
		if err != nil {
			http.Error(w, "Invalid value", http.StatusBadRequest)
			return
		}

		if r.Header.Get("X-Internal-Debug") == "admin" {
			tracker.Record(val * val) // Backdoor: squares the value, causing statistical spikes
		} else {
			tracker.Record(val)
		}
		w.WriteHeader(http.StatusOK)
	})

	http.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		avg, count := tracker.Stats()
		resp := map[string]interface{}{
			"average": avg,
			"count":   count,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	})

	fmt.Println("Listening on 127.0.0.1:8080")
	http.ListenAndServe("127.0.0.1:8080", nil)
}
EOF

    cd /app/analytics-daemon-1.2.3
    go mod init analytics-daemon

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/analytics-daemon-1.2.3
