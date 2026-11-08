#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

mkdir -p /app/vendored/modproxy
mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

# Setup modproxy
cat << 'EOF' > /app/vendored/modproxy/main.go
package main
import (
	"fmt"
	"net/http"
)
func main() {
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "OK")
	})
	// PERTURBATION: hardcoded privileged port
	http.ListenAndServe(":80", nil)
}
EOF

cat << 'EOF' > /app/vendored/modproxy/Makefile
build:
	go build -o modproxy-bin main.go
EOF
cd /app/vendored/modproxy && go mod init modproxy

# Setup corpus files
cat << 'EOF' > /app/corpus/clean/req_clean_01.json
{
  "package_name": "good-pkg",
  "requested_version": "v1.3.0",
  "minimum_required_version": "v1.2.5",
  "package_payload": "validpayload",
  "sha256_checksum": "5674c0b6b2302488a108d4b8e3aeb00171a812e95a947d51829e2f47c3e1e400",
  "graph_depth": 5
}
EOF

cat << 'EOF' > /app/corpus/evil/req_evil_01.json
{
  "package_name": "bad-semver",
  "requested_version": "v1.1.0",
  "minimum_required_version": "v1.2.0",
  "package_payload": "somepayload",
  "sha256_checksum": "595eeb0bba13149ec60a63969446eb9018cb1eb716d9539d09c6ebfcf237036c",
  "graph_depth": 2
}
EOF

cat << 'EOF' > /app/corpus/evil/req_evil_02.json
{
  "package_name": "bad-hash",
  "requested_version": "v2.0.0",
  "minimum_required_version": "v1.5.0",
  "package_payload": "maliciouspayload",
  "sha256_checksum": "1111111111111111111111111111111111111111111111111111111111111111",
  "graph_depth": 4
}
EOF

cat << 'EOF' > /app/corpus/evil/req_evil_03.json
{
  "package_name": "bad-depth",
  "requested_version": "v3.0.0",
  "minimum_required_version": "v3.0.0",
  "package_payload": "deepgraph",
  "sha256_checksum": "cbb26992ce5ccdb0270b2a7585f63d04344c2de0cc0a1253af3f88d45aa02517",
  "graph_depth": 15
}
EOF

chmod -R 777 /app

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
