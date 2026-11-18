#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go sox
pip3 install pytest

mkdir -p /app/ingest

# Generate DTMF audio
cat << 'EOF' > /tmp/gen_audio.py
import wave, math, struct
def generate_dtmf(sequence, filename):
    freqs = {
        '0': (941, 1336), '1': (697, 1209), '2': (697, 1336), '3': (697, 1477),
        '4': (770, 1209), '5': (770, 1336), '6': (770, 1477),
        '7': (852, 1209), '8': (852, 1336), '9': (852, 1477)
    }
    sample_rate = 8000
    duration = 0.2
    pause = 0.1

    with wave.open(filename, 'w') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sample_rate)

        for char in sequence:
            f1, f2 = freqs[char]
            for i in range(int(sample_rate * duration)):
                t = float(i) / sample_rate
                val = int(32767.0 * 0.5 * (math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t)))
                f.writeframesraw(struct.pack('<h', val))
            for i in range(int(sample_rate * pause)):
                f.writeframesraw(struct.pack('<h', 0))

generate_dtmf('8675309', '/app/alert_log.wav')
EOF
python3 /tmp/gen_audio.py

# Generate requests log
cat << 'EOF' > /tmp/gen_logs.py
import json, random
with open('/app/requests.log', 'w') as f:
    for i in range(100):
        f.write(json.dumps({"user_id": 4044, "endpoint": "/api", "status": 500}) + "\n")
    for i in range(5):
        f.write(json.dumps({"user_id": 1234, "endpoint": "/api", "status": 500}) + "\n")
    for i in range(500):
        f.write(json.dumps({"user_id": random.randint(1000, 4000), "endpoint": "/api", "status": 200}) + "\n")
EOF
python3 /tmp/gen_logs.py

# Create Go service
cat << 'EOF' > /app/ingest/main.go
package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
)

var dataStore = make(map[int]string)

type Payload struct {
	UserID  int    `json:"user_id"`
	Payload string `json:"payload"`
}

func ingestHandler(w http.ResponseWriter, r *http.Request) {
	var p Payload
	if err := json.NewDecoder(r.Body).Decode(&p); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	decoded, err := base64.StdEncoding.DecodeString(p.Payload)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Race condition bug
	dataStore[p.UserID] = string(decoded)

	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "Success")
}

func main() {
	http.HandleFunc("/ingest", ingestHandler)
	http.ListenAndServe(":9000", nil)
}
EOF

cd /app/ingest && go mod init ingest

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
