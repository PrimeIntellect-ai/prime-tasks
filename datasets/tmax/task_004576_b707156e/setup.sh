#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang-go curl
    pip3 install pytest

    mkdir -p /app/gateway /app/backend /app/legacy_bin /app/logs

    # 1. Create the legacy binary with the hardcoded key
    cat << 'EOF' > /app/legacy_bin/vault_extractor.c
#include <stdio.h>
int main() {
    char* secret = "AES_KEY_8f9a2b3c4d5e6f7a8b9c0d1e2f3a4b5c";
    printf("Utility loaded.\n");
    return 0;
}
EOF
    gcc /app/legacy_bin/vault_extractor.c -o /app/legacy_bin/vault_extractor
    rm /app/legacy_bin/vault_extractor.c

    # 2. Create the vulnerable backend service
    cat << 'EOF' > /app/backend/main.go
package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
)

type Payload struct {
	UserToken string `json:"user_token"`
	Data      string `json:"data"`
}

func processHandler(w http.ResponseWriter, r *http.Request) {
	body, _ := ioutil.ReadAll(r.Body)

	// Vulnerability: Logging sensitive data
	f, _ := os.OpenFile("/app/logs/backend.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	f.WriteString(string(body) + "\n")
	f.Close()

	var p Payload
	json.Unmarshal(body, &p)

	// Currently returns plaintext; agent must change to AES-GCM using NEW_MASTER_KEY
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"encrypted_data": "%s"}`, p.Data)
}

func main() {
	http.HandleFunc("/process", processHandler)
	log.Fatal(http.ListenAndServe("127.0.0.1:9090", nil))
}
EOF

    # 3. Create the gateway service
    cat << 'EOF' > /app/gateway/main.go
package main

import (
	"bytes"
	"io/ioutil"
	"log"
	"net/http"
)

func apiHandler(w http.ResponseWriter, r *http.Request) {
	body, _ := ioutil.ReadAll(r.Body)

	resp, err := http.Post("http://127.0.0.1:9090/process", "application/json", bytes.NewBuffer(body))
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	respBody, _ := ioutil.ReadAll(resp.Body)

	// Agent must add CSP headers here
	w.Header().Set("Content-Type", "application/json")
	w.Write(respBody)
}

func main() {
	http.HandleFunc("/api/v1/data", apiHandler)
	log.Fatal(http.ListenAndServe("127.0.0.1:8080", nil))
}
EOF

    chmod -R 777 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
