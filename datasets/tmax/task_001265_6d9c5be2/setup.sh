#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go nginx curl
    pip3 install pytest pycryptodome

    mkdir -p /app/nginx /app/auth /app/resource /app/corpus/clean /app/corpus/evil /home/user/validator

    # Nginx config
    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            return 200 "OK\n";
        }
        location /resource {
            proxy_pass http://127.0.0.1:8082;
        }
    }
}
EOF

    # Auth service Go code
    cat << 'EOF' > /app/auth/main.go
package main
import (
    "fmt"
    "net/http"
)
func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintln(w, "Auth Service")
    })
    http.ListenAndServe(":8081", nil)
}
EOF
    cd /app/auth && go build -o auth-svc main.go && rm main.go

    # Resource service Go code
    cat << 'EOF' > /app/resource/main.go
package main
import (
    "fmt"
    "net/http"
)
func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintln(w, "Resource Service")
    })
    http.ListenAndServe(":8082", nil)
}
EOF
    cd /app/resource && go build -o resource-svc main.go && rm main.go

    # Startup script
    cat << 'EOF' > /app/start.sh
#!/bin/bash
nginx -c /app/nginx/nginx.conf &
/app/auth/auth-svc &
/app/resource/resource-svc &
sleep 2
EOF
    chmod +x /app/start.sh

    # Token generator script
    cat << 'EOF' > /app/generate_tokens.py
import os
import json
import base64
import hashlib
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad

KEY = b'SuperSecretKey12'

def generate_token(user, role, evil=False):
    checksum = hashlib.md5((user + role).encode()).hexdigest()
    if evil:
        checksum = hashlib.md5((user + "user").encode()).hexdigest() # Invalid checksum for 'admin'

    payload = json.dumps({"user": user, "role": role, "checksum": checksum})
    iv = os.urandom(16)
    cipher = AES.new(KEY, AES.MODE_CBC, iv)
    ct_bytes = cipher.encrypt(pad(payload.encode(), AES.block_size))

    if evil:
        # Bit-flipping to change "user" to "admin"
        # We'll just encrypt directly with "admin" but bad checksum to simulate the result
        payload = json.dumps({"user": user, "role": "admin", "checksum": checksum})
        cipher = AES.new(KEY, AES.MODE_CBC, iv)
        ct_bytes = cipher.encrypt(pad(payload.encode(), AES.block_size))

    return base64.b64encode(iv + ct_bytes).decode('utf-8')

for i in range(50):
    user = f"user{i}"
    clean_token = generate_token(user, "user", evil=False)
    with open(f"/app/corpus/clean/token_{i}.txt", "w") as f:
        f.write(clean_token)

    evil_token = generate_token(user, "admin", evil=True)
    with open(f"/app/corpus/evil/token_{i}.txt", "w") as f:
        f.write(evil_token)
EOF
    python3 /app/generate_tokens.py
    rm /app/generate_tokens.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
