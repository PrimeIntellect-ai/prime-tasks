#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang upx-ucl binutils gdb
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/beacon_gen.go
package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io/ioutil"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		return
	}
	data, err := ioutil.ReadFile(os.Args[1])
	if err != nil {
		return
	}
	var m map[string]interface{}
	if err := json.Unmarshal(data, &m); err != nil {
		return
	}

	ip, _ := m["client_ip"].(string)
	sni, _ := m["tls_sni"].(string)

	msg := ip + "|" + sni
	key := []byte{0x13, 0x37, 0xBE, 0xEF}
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(msg))
	expectedMAC := hex.EncodeToString(mac.Sum(nil))

	m["x_c2_mac"] = expectedMAC

	out, _ := json.Marshal(m)
	ioutil.WriteFile(os.Args[1], out, 0644)
}
EOF

    cd /app
    go build -ldflags="-s -w" -o beacon_gen beacon_gen.go
    upx beacon_gen
    rm beacon_gen.go

    mkdir -p /home/user/evidence/clean
    mkdir -p /home/user/evidence/evil

    cat << 'EOF' > /app/gen_logs.py
import json
import random
import os
import hmac
import hashlib

key = b'\x13\x37\xBE\xEF'

for i in range(50):
    ip = f"192.168.1.{random.randint(1, 254)}"
    sni = f"example{i}.com"

    clean_log = {"client_ip": ip, "tls_sni": sni, "csp_report": {"document-uri": "http://test.com"}}
    with open(f"/home/user/evidence/clean/log_{i}.json", "w") as f:
        json.dump(clean_log, f)

    evil_log = {"client_ip": ip, "tls_sni": sni, "csp_report": {"document-uri": "http://test.com"}}
    msg = f"{ip}|{sni}".encode()
    mac = hmac.new(key, msg, hashlib.sha256).hexdigest()
    evil_log["x_c2_mac"] = mac
    with open(f"/home/user/evidence/evil/log_{i}.json", "w") as f:
        json.dump(evil_log, f)
EOF

    python3 /app/gen_logs.py
    rm /app/gen_logs.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
