#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang expect openssl socat curl
    pip3 install pytest

    mkdir -p /app/vendored/prober-cli
    mkdir -p /app/scripts
    mkdir -p /app/url_corpus/evil
    mkdir -p /app/url_corpus/clean

    # Setup Vendored Package
    cat << 'EOF' > /app/vendored/prober-cli/Makefile
build:
	go build -o prober cli.go
EOF

    cat << 'EOF' > /app/vendored/prober-cli/main.go
package main
import (
    "fmt"
    "net/http"
    "os"
    "time"
    "crypto/tls"
)
const defaultTimeout = 5 * time.Nanosecond
func main() {
    if len(os.Args) < 2 { os.Exit(1) }
    url := os.Args[len(os.Args)-1]
    client := &http.Client{
        Timeout: defaultTimeout,
        Transport: &http.Transport{
            TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
        },
    }
    resp, err := client.Get(url)
    if err != nil {
        fmt.Printf("ERROR: %v\n", err)
        os.Exit(1)
    }
    defer resp.Body.Close()
    fmt.Printf("STATUS: %s\n", resp.Status)
}
EOF

    # Setup Gen Cert Script
    cat << 'EOF' > /app/scripts/gen_cert.sh
#!/bin/bash
read -p "Enter passphrase: " PASS
if [ "$PASS" != "sre-secure" ]; then
    echo "Unauthorized"
    exit 1
fi
openssl req -x509 -newkey rsa:2048 -keyout /home/user/server.key -out /home/user/server.crt -days 365 -nodes -subj "/CN=localhost" 2>/dev/null
echo "Success"
EOF
    chmod +x /app/scripts/gen_cert.sh

    # Setup Corpora
    cat << 'EOF' > /app/url_corpus/evil/ssrf_urls.txt
http://169.254.169.254/latest/meta-data/
https://127.0.0.1:8443/health
http://10.0.0.1/admin
ftp://public.com/file
http://192.168.1.1/router
EOF

    cat << 'EOF' > /app/url_corpus/clean/valid_urls.txt
https://www.google.com/
http://93.184.216.34/
https://github.com/status
EOF

    useradd -m -s /bin/bash user || true

    touch /var/log/prober.log
    chown user:user /var/log/prober.log

    chmod -R 777 /home/user
