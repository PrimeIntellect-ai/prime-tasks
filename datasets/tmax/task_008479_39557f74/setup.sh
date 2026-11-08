#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit
    cd /home/user/audit

    cat << 'EOF' > admin_cli_real.go
package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"flag"
	"fmt"
	"os"
	"strings"
)

// Hardcoded secret (CWE-798)
var secretKey = []byte("S3cur1ty_H@rdc0d3d_99!")

func generateMAC(message, key []byte) []byte {
	mac := hmac.New(sha256.New, key)
	mac.Write(message)
	return mac.Sum(nil)
}

func verifyToken(token string) (string, string, bool) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return "", "", false
	}

	message := parts[0] + "." + parts[1]
	expectedMAC := generateMAC([]byte(message), secretKey)
	expectedMACBase64 := base64.RawURLEncoding.EncodeToString(expectedMAC)

	if parts[2] != expectedMACBase64 {
		return "", "", false
	}

	user, _ := base64.RawURLEncoding.DecodeString(parts[0])
	role, _ := base64.RawURLEncoding.DecodeString(parts[1])

	return string(user), string(role), true
}

func main() {
	tokenPtr := flag.String("token", "", "Authentication token")
	actionPtr := flag.String("action", "", "Action to perform")
	flag.Parse()

	if *tokenPtr == "" || *actionPtr == "" {
		fmt.Println("Usage: admin_cli --token <token> --action <action>")
		os.Exit(1)
	}

	user, role, valid := verifyToken(*tokenPtr)
	if !valid {
		fmt.Println("Error: Invalid token signature.")
		os.Exit(1)
	}

	if *actionPtr == "get_flag" {
		if user == "admin" && role == "superuser" {
			fmt.Println("FLAG{h4rdc0d3d_s3cr3ts_r_b4d}")
		} else {
			fmt.Println("Error: Insufficient privileges.")
		}
	} else {
		fmt.Println("Error: Unknown action.")
	}
}
EOF

    go build -o admin_cli admin_cli_real.go
    chmod +x admin_cli

    cat << 'EOF' > admin_cli.go
package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"flag"
	"fmt"
	"os"
	"strings"
)

// Hardcoded secret (REDACTED FOR SECURITY AUDIT)
var secretKey = []byte("REDACTED_SECRET_KEY")

func generateMAC(message, key []byte) []byte {
	mac := hmac.New(sha256.New, key)
	mac.Write(message)
	return mac.Sum(nil)
}

func verifyToken(token string) (string, string, bool) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return "", "", false
	}

	message := parts[0] + "." + parts[1]
	expectedMAC := generateMAC([]byte(message), secretKey)
	expectedMACBase64 := base64.RawURLEncoding.EncodeToString(expectedMAC)

	if parts[2] != expectedMACBase64 {
		return "", "", false
	}

	user, _ := base64.RawURLEncoding.DecodeString(parts[0])
	role, _ := base64.RawURLEncoding.DecodeString(parts[1])

	return string(user), string(role), true
}

func main() {
	tokenPtr := flag.String("token", "", "Authentication token")
	actionPtr := flag.String("action", "", "Action to perform")
	flag.Parse()

	if *tokenPtr == "" || *actionPtr == "" {
		fmt.Println("Usage: admin_cli --token <token> --action <action>")
		os.Exit(1)
	}

	user, role, valid := verifyToken(*tokenPtr)
	if !valid {
		fmt.Println("Error: Invalid token signature.")
		os.Exit(1)
	}

	if *actionPtr == "get_flag" {
		if user == "admin" && role == "superuser" {
			// Prints the flag
			fmt.Println("FLAG{REDACTED}")
		} else {
			fmt.Println("Error: Insufficient privileges.")
		}
	} else {
		fmt.Println("Error: Unknown action.")
	}
}
EOF

    rm admin_cli_real.go

    chmod -R 777 /home/user
