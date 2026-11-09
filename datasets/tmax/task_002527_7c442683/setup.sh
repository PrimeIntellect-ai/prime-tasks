#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak golang git curl
pip3 install pytest

mkdir -p /app
espeak -w /app/voicemail.wav "System alert core router temperature critical"

mkdir -p /home/user/voicemail-api
cd /home/user/voicemail-api

git init
git config user.email "dev@company.local"
git config user.name "Dev"

cat << 'EOF' > go.mod
module voicemail-api

go 1.20

require (
	github.com/sirupsen/logrus v1.9.0
	github.com/google/uuid v1.1.0 // CONFLICT: intended to be v1.3.0
)
EOF

cat << 'EOF' > main.go
package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os/exec"
	"sync"
)

var authSecret = "sup3r_s3cr3t_v2_f0r3ns1cs"

type Processor struct {
	mu sync.Mutex
}

func (p *Processor) Transcribe(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Authorization") != "Bearer "+authSecret {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	p.mu.Lock()
	// BUG: Deadlock. Intentionally locking twice to simulate the contention bug
	p.mu.Lock()
	defer p.mu.Unlock()

    // Stub transcription logic using espeak/whisper simulation via shell
	cmd := exec.Command("espeak", "-q", "-x", "test")
	cmd.Run()

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"transcript": "System alert core router temperature critical"}`))
}

func main() {
	p := &Processor{}
	http.HandleFunc("/api/v1/transcribe", p.Transcribe)
	log.Fatal(http.ListenAndServe("127.0.0.1:8080", nil))
}
EOF

git add .
git commit -m "Initial commit with hardcoded secret"

sed -i 's/var authSecret = "sup3r_s3cr3t_v2_f0r3ns1cs"/var authSecret = os.Getenv("API_TOKEN")/' main.go
sed -i '11i\	"os"' main.go

git add main.go
git commit -m "Secure API token and update deps"

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chown -R user:user /app
chmod -R 777 /home/user
