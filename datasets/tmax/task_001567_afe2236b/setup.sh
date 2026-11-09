#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang redis-server wget curl
    pip3 install pytest

    # Install MinIO
    wget https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio
    chmod +x /usr/local/bin/minio

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /home/user/app

    # Python script to generate corpus
    cat << 'EOF' > /tmp/gen_corpus.py
import struct
import os

def create_file(path, encoding, payload):
    with open(path, 'wb') as f:
        f.write(b'BKP1')
        enc_bytes = encoding.encode('ascii')
        f.write(struct.pack('B', len(enc_bytes)))
        f.write(enc_bytes)
        payload_bytes = payload.encode(encoding)
        f.write(struct.pack('<I', len(payload_bytes)))
        f.write(payload_bytes)

create_file('/app/corpus/clean/sample1.bin', 'UTF-8', 'normal config diff 1')
create_file('/app/corpus/clean/sample2.bin', 'UTF-16LE', 'normal config diff 2')
create_file('/app/corpus/evil/sample1.bin', 'UTF-16LE', 'some EXEC_BASH command')
create_file('/app/corpus/evil/sample2.bin', 'Windows-1252', 'connect to /dev/tcp/1.1.1.1/80')
EOF
    python3 /tmp/gen_corpus.py

    # Create server.go
    cat << 'EOF' > /home/user/app/server.go
package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
)

func uploadHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Error reading body", http.StatusInternalServerError)
		return
	}
	// Currently directly interacts with MinIO/Redis without filtering
	fmt.Println("Received upload of size", len(body))
	w.WriteHeader(http.StatusOK)
}

func main() {
	http.HandleFunc("/upload", uploadHandler)
	fmt.Println("Starting server on :8080")
	http.ListenAndServe(":8080", nil)
}
EOF

    # Create start.sh
    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
MINIO_ROOT_USER=admin MINIO_ROOT_PASSWORD=password minio server /data &
cd /home/user/app && go run server.go &
wait
EOF
    chmod +x /app/start.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
