#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go openssl
    pip3 install pytest

    mkdir -p /home/user/certs /home/user/logs

    # Generate Root CA
    openssl req -x509 -sha256 -days 3650 -nodes -newkey rsa:2048 \
      -subj "/CN=TrustedRootCA" \
      -keyout /home/user/certs/root.key -out /home/user/certs/root.pem

    # Generate Leaf Cert
    openssl req -new -newkey rsa:2048 -nodes \
      -keyout /home/user/certs/leaf.key -out /home/user/certs/leaf.csr \
      -subj "/CN=secure.internal.com"

    echo "subjectAltName=DNS:secure.internal.com" > /tmp/extfile.cnf
    openssl x509 -req -in /home/user/certs/leaf.csr -CA /home/user/certs/root.pem \
      -CAkey /home/user/certs/root.key -CAcreateserial -out /home/user/certs/leaf.pem -days 365 -sha256 \
      -extfile /tmp/extfile.cnf

    # Create transaction log
    cat << 'EOF' > /home/user/logs/transactions.log
[INFO] Transaction 101 started. User: alice.
[DEBUG] Processing payment method: 1234-5678-9012-3456
[INFO] Transaction 101 successful.
[DEBUG] User bob backup payment: 9999-8888-7777-6666 (Visa)
[INFO] End of log.
EOF

    # Create buggy checker
    cat << 'EOF' > /home/user/buggy_checker.go
package main

import (
	"crypto/tls"
	"fmt"
	"os"
)

func main() {
	if len(os.Args) != 4 {
		fmt.Println("Usage: buggy_checker <leaf> <root> <log>")
		os.Exit(1)
	}
	leafPath := os.Args[1]
	logPath := os.Args[3]

	// CWE-295: Improper Certificate Validation
	// Pretending to verify, but actually skipping
	_ = leafPath
	config := &tls.Config{InsecureSkipVerify: true}
	_ = config

	fmt.Println("Certificate verified (mocked).")

	logData, err := os.ReadFile(logPath)
	if err != nil {
		panic(err)
	}

	// No redaction done
	fmt.Print(string(logData))
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
