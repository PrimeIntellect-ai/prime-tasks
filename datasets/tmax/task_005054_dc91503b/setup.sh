#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server golang curl openssl
    pip3 install pytest

    mkdir -p /app/certs /app/nginx /app/keys /app/corpus/clean /app/corpus/evil

    # Generate CA and Server certs
    openssl req -x509 -newkey rsa:4096 -keyout /app/certs/ca.key -out /app/certs/ca.crt -days 365 -nodes -subj "/CN=MyCA"
    openssl genrsa -out /app/certs/server.key 2048
    openssl req -new -key /app/certs/server.key -out /app/certs/server.csr -subj "/CN=127.0.0.1"
    openssl x509 -req -in /app/certs/server.csr -CA /app/certs/ca.crt -CAkey /app/certs/ca.key -CAcreateserial -out /app/certs/server.crt -days 365

    # Nginx config
    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://127.0.0.1:8443;
        }
    }
}
EOF

    # Go Auth Service
    cat << 'EOF' > /app/auth.go
package main

import (
	"crypto/tls"
	"crypto/x509"
	"io/ioutil"
	"log"
	"net/http"
)

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status": "ok"}`))
}

func main() {
	caCert, err := ioutil.ReadFile("/app/certs/ca.crt")
	if err != nil {
		log.Fatal(err)
	}
	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	tlsConfig := &tls.Config{
		ClientCAs:  caCertPool,
		ClientAuth: tls.RequireAndVerifyClientCert,
	}

	server := &http.Server{
		Addr:      "127.0.0.1:8443",
		TLSConfig: tlsConfig,
	}

	http.HandleFunc("/health", healthHandler)
	log.Fatal(server.ListenAndServeTLS("/app/certs/server.crt", "/app/certs/server.key"))
}
EOF

    cd /app && go build -o auth auth.go

    # Start script
    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx/nginx.conf
cd /app && ./auth &
sleep 2
EOF
    chmod +x /app/start.sh

    # Generate AES key and corpus
    cat << 'EOF' > /app/setup_corpus.go
package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"io"
	"os"
)

func encrypt(keyHex, plaintext string) string {
	key, _ := hex.DecodeString(keyHex)
	block, _ := aes.NewCipher(key)
	nonce := make([]byte, 12)
	io.ReadFull(rand.Reader, nonce)
	aesgcm, _ := cipher.NewGCM(block)
	ciphertext := aesgcm.Seal(nil, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(append(nonce, ciphertext...))
}

func main() {
	keyHex := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	os.WriteFile("/app/keys/aes.key", []byte(keyHex), 0644)

	clean := encrypt(keyHex, `{"user": "alice"}`)
	os.WriteFile("/app/corpus/clean/1.txt", []byte(clean), 0644)

	evil := encrypt(keyHex, `{"user": "admin' --"}`)
	os.WriteFile("/app/corpus/evil/1.txt", []byte(evil), 0644)
}
EOF
    cd /app && go run setup_corpus.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
