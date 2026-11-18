#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go nginx openssl curl
    pip3 install pytest

    mkdir -p /app/certs /app/nginx /app/backend

    # Generate CA and Certs
    openssl req -x509 -newkey rsa:2048 -keyout /app/certs/ca.key -out /app/certs/ca.crt -days 365 -nodes -subj "/CN=MyRootCA"
    openssl req -newkey rsa:2048 -keyout /app/certs/server.key -out /app/certs/server.csr -nodes -subj "/CN=localhost"
    openssl x509 -req -in /app/certs/server.csr -CA /app/certs/ca.crt -CAkey /app/certs/ca.key -CAcreateserial -out /app/certs/server.crt -days 365
    openssl req -newkey rsa:2048 -keyout /app/certs/client.key -out /app/certs/client.csr -nodes -subj "/CN=TestClient"
    openssl x509 -req -in /app/certs/client.csr -CA /app/certs/ca.crt -CAkey /app/certs/ca.key -CAcreateserial -out /app/certs/client.crt -days 365

    # Create Backend
    cat << 'EOF' > /app/backend/backend.go
package main
import (
	"fmt"
	"net/http"
)
func handler(w http.ResponseWriter, r *http.Request) {
	cn := r.Header.Get("X-Client-CN")
	if cn != "TestClient" {
		http.Error(w, "Invalid CN", 403)
		return
	}
	fmt.Fprintf(w, "OK")
}
func main() {
	http.HandleFunc("/", handler)
	http.ListenAndServe("127.0.0.1:8080", nil)
}
EOF
    cd /app/backend && go build -o server backend.go

    # Create basic nginx config skeleton
    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        # TODO: Configure mTLS proxy here
    }
}
EOF

    # Create start script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
/app/backend/server &
nginx -c /app/nginx/nginx.conf
EOF
    chmod +x /app/start_services.sh

    # Oracle implementation
    cat << 'EOF' > /app/oracle.go
package main

import (
	"bufio"
	"crypto/x509"
	"encoding/pem"
	"io/ioutil"
	"net/http"
	"os"
	"strings"
)

func main() {
	certPEM, err := ioutil.ReadFile("/app/certs/client.crt")
	if err != nil {
		panic(err)
	}
	block, _ := pem.Decode(certPEM)
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		panic(err)
	}
	cn := cert.Subject.CommonName

	req, err := http.ReadRequest(bufio.NewReader(os.Stdin))
	if err != nil {
		panic(err)
	}

	req.Header.Set("X-Cert-CN", cn)

	for _, cookie := range req.Cookies() {
		if cookie.Name == "legacy_auth" && cookie.Value == "1" {
			req.Header.Set("X-Legacy-Bypass", "true")
			break
		}
	}

	ua := req.Header.Get("User-Agent")
	if ua == "" {
		req.Header.Set("User-Agent", "inspected")
	} else {
		req.Header.Set("User-Agent", ua+" - inspected")
	}

	if strings.HasPrefix(req.Host, "internal-") {
		req.URL.Path = "/admin/debug" + req.URL.Path
	}

	req.Write(os.Stdout)
}
EOF
    cd /app && go build -o oracle_modifier oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
