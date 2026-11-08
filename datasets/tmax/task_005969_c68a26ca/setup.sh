#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    cat << 'EOF' > /home/user/app/main.go
package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

var logKey = []byte("supersecret32bytekey123456789012") // 32 bytes for AES-256

type RotationLog struct {
	Timestamp   int64  `json:"timestamp"`
	Action      string `json:"action"`
	RotationID  string `json:"rotation_id"`
	NewCredHash string `json:"new_cred_hash"`
}

func encryptLog(data []byte) (string, error) {
	block, err := aes.NewCipher(logKey)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err = io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	ciphertext := gcm.Seal(nonce, nonce, data, nil)
	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

func rotateHandler(w http.ResponseWriter, r *http.Request) {
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
		http.Error(w, "Missing token", http.StatusUnauthorized)
		return
	}
	token := strings.TrimPrefix(authHeader, "Bearer ")

	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		http.Error(w, "Invalid token format", http.StatusUnauthorized)
		return
	}

	headerBytes, _ := base64.RawURLEncoding.DecodeString(parts[0])
	var header map[string]interface{}
	json.Unmarshal(headerBytes, &header)

	payloadBytes, _ := base64.RawURLEncoding.DecodeString(parts[1])
	var payload map[string]interface{}
	json.Unmarshal(payloadBytes, &payload)

	// Vulnerability: alg=none bypass
	if alg, ok := header["alg"].(string); ok && alg == "none" {
		// Skip signature verification
	} else {
		// Mock signature check failure
		http.Error(w, "Invalid signature", http.StatusUnauthorized)
		return
	}

	if role, ok := payload["role"].(string); !ok || role != "admin" {
		http.Error(w, "Forbidden: Admins only", http.StatusForbidden)
		return
	}

	var reqBody map[string]string
	json.NewDecoder(r.Body).Decode(&reqBody)
	newCred := reqBody["new_credential"]
	if newCred == "" {
		http.Error(w, "Missing new_credential", http.StatusBadRequest)
		return
	}

	rotID := "ROT-" + fmt.Sprintf("%d", time.Now().UnixNano())
	logEntry := RotationLog{
		Timestamp:   time.Now().Unix(),
		Action:      "credential_rotation",
		RotationID:  rotID,
		NewCredHash: "hash_placeholder",
	}

	logBytes, _ := json.Marshal(logEntry)
	encLog, _ := encryptLog(logBytes)

	f, _ := os.OpenFile("/home/user/app/audit.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	defer f.Close()
	f.WriteString(encLog + "\n")

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status": "success"}`))
}

func main() {
	http.HandleFunc("/admin/rotate", rotateHandler)
	http.ListenAndServe(":8080", nil)
}
EOF

    cd /home/user/app
    go mod init app

    chmod -R 777 /home/user
