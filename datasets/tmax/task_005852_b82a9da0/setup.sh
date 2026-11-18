#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go openssl curl procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.certs
    mkdir -p /home/user/app/uploads

    openssl req -x509 -newkey rsa:4096 -keyout /home/user/.certs/key.pem -out /home/user/.certs/cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

    cat << 'EOF' > /home/user/server.go
package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

func uploadHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	defer file.Close()

	filename := header.Filename

	if strings.Contains(filename, "../") {
		logFile, _ := os.OpenFile("/home/user/waf.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0666)
		if logFile != nil {
			logFile.WriteString(fmt.Sprintf("[WARN] Suspicious path traversal pattern detected. AlertID: WAF-PT-9921 | IP: 127.0.0.1 | Payload: %s\n", filename))
			logFile.Close()
		}
	}

	out, err := os.Create("/home/user/app/uploads/" + filename)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer out.Close()

	io.Copy(out, file)
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("File uploaded successfully"))
}

func main() {
	http.HandleFunc("/upload", uploadHandler)
	err := http.ListenAndServeTLS("127.0.0.1:8443", "/home/user/.certs/cert.pem", "/home/user/.certs/key.pem", nil)
	if err != nil {
		log.Fatal(err)
	}
}
EOF

    go build -o /usr/local/bin/server /home/user/server.go
    rm /home/user/server.go

    cat << 'EOF' > /home/user/upload_handler.go
func uploadHandler(w http.ResponseWriter, r *http.Request) {
	file, header, err := r.FormFile("file")
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	defer file.Close()

	filename := header.Filename

	// WAF Middleware logic (simplified)
	if strings.Contains(filename, "../") {
		logWAFAlert(filename)
	}

	// Vulnerable file write
	out, err := os.Create("/home/user/app/uploads/" + filename)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer out.Close()

	io.Copy(out, file)
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("File uploaded successfully"))
}
EOF

    # Wrap python3 and bash to ensure server is running
    mv /usr/bin/python3 /usr/bin/python3_real
    cat << 'EOF' > /usr/bin/python3
#!/bin/bash
if ! pgrep -x "server" > /dev/null; then
    su - user -c "/usr/local/bin/server &"
    sleep 1
fi
exec /usr/bin/python3_real "$@"
EOF
    chmod +x /usr/bin/python3

    mv /bin/bash /bin/bash_real
    cat << 'EOF' > /bin/bash
#!/bin/bash_real
if ! pgrep -x "server" > /dev/null; then
    su - user -c "/usr/local/bin/server &"
    sleep 1
fi
exec /bin/bash_real "$@"
EOF
    chmod +x /bin/bash

    chown -R user:user /home/user
    chmod -R 777 /home/user
