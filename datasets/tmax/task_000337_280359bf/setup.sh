#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip e2fsprogs golang-go
    pip3 install pytest

    # Create application directory
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create 50MB ext4 image
    dd if=/dev/zero of=/app/user_data.img bs=1M count=50
    mkfs.ext4 -F /app/user_data.img

    # Populate clean corpus
    cat << 'EOF' > /app/corpus/clean/1.json
{"username": "alice", "data": "update"}
EOF

    cat << 'EOF' > /app/corpus/clean/2.json
{"username": "bob", "data": "new_account"}
EOF

    # Populate evil corpus
    cat << 'EOF' > /app/corpus/evil/1.json
{"username": "../../../etc/passwd", "data": "hack"}
EOF

    cat << 'EOF' > /app/corpus/evil/2.json
{"username": "bob; rm -rf /", "data": "bad"}
EOF

    cat << 'EOF' > /app/corpus/evil/3.json
{"username": "admin", "data": "REALLY_LONG_STRING_HERE_THAT_EXCEEDS_256_CHARACTERS_01234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"}
EOF

    # Create legacy auth processor (stripped Go binary)
    cat << 'EOF' > /tmp/legacy.go
package main

import (
    "encoding/json"
    "net/http"
    "os"
    "path/filepath"
)

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        var p map[string]string
        json.NewDecoder(r.Body).Decode(&p)
        if u, ok := p["username"]; ok {
            os.WriteFile(filepath.Join("/home/user/user_data_mnt", u+".dat"), []byte(p["data"]), 0644)
        }
        w.Write([]byte(`{"status":"processed"}`))
    })
    http.ListenAndServe("127.0.0.1:9090", nil)
}
EOF

    go build -ldflags="-s -w" -o /app/legacy_auth_processor /tmp/legacy.go
    rm /tmp/legacy.go
    chmod +x /app/legacy_auth_processor

    # Cleanup build dependencies
    apt-get remove -y golang-go
    apt-get autoremove -y

    # Set permissions for /app
    chmod -R 777 /app

    # Create user and set home directory permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
