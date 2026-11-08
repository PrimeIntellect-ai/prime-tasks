#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang nginx openssl
pip3 install pytest PyJWT cryptography flask

mkdir -p /app/certs /app/data /app/oracle
mkdir -p /home/user

# Generate RSA keypair
openssl genpkey -algorithm RSA -out /app/certs/private.pem -pkeyopt rsa_keygen_bits:2048
openssl rsa -pubout -in /app/certs/private.pem -out /app/certs/public.pem

# Generate dummy data
echo '{"status": "production", "version": "1.0.4"}' > /app/data/critical_config.json

# Compile Go oracle
cat << 'EOF' > /app/oracle/main.go
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io/ioutil"
	"os"
	"strings"

	"github.com/golang-jwt/jwt/v4"
)

func main() {
	inputBytes, err := ioutil.ReadAll(os.Stdin)
	if err != nil {
		fmt.Println("MALFORMED")
		return
	}
	tokenString := strings.TrimSpace(string(inputBytes))

	parts := strings.Split(tokenString, ".")
	if len(parts) != 3 {
		fmt.Println("MALFORMED")
		return
	}

	pubKeyBytes, err := ioutil.ReadFile("/app/certs/public.pem")
	if err != nil {
		fmt.Println("MALFORMED")
		return
	}
	pubKey, err := jwt.ParseRSAPublicKeyFromPEM(pubKeyBytes)
	if err != nil {
		fmt.Println("MALFORMED")
		return
	}

	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("REJECTED_ALG")
		}
		return pubKey, nil
	})

	if err != nil {
		if strings.Contains(err.Error(), "REJECTED_ALG") || strings.Contains(err.Error(), "signing method") {
			fmt.Println("REJECTED_ALG")
			return
		}
		if strings.Contains(err.Error(), "signature is invalid") || strings.Contains(err.Error(), "crypto/rsa: verification error") {
			fmt.Println("INVALID_SIG")
			return
		}
		if strings.Contains(err.Error(), "invalid number of segments") || strings.Contains(err.Error(), "illegal base64") {
			fmt.Println("MALFORMED")
			return
		}
		fmt.Println("INVALID_SIG")
		return
	}

	if !token.Valid {
		fmt.Println("INVALID_SIG")
		return
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		fmt.Println("INTEGRITY_FAIL")
		return
	}

	fileHashClaim, ok := claims["file_hash"].(string)
	if !ok {
		fmt.Println("INTEGRITY_FAIL")
		return
	}

	configBytes, err := ioutil.ReadFile("/app/data/critical_config.json")
	if err != nil {
		fmt.Println("INTEGRITY_FAIL")
		return
	}
	hash := sha256.Sum256(configBytes)
	expectedHash := hex.EncodeToString(hash[:])

	if fileHashClaim != expectedHash {
		fmt.Println("INTEGRITY_FAIL")
		return
	}

	fmt.Println("VALID")
}
EOF

cd /app/oracle
go mod init oracle
go get github.com/golang-jwt/jwt/v4
go build -o token_validator_bin main.go

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
