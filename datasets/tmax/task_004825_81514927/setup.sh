#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go wget curl unzip make
    pip3 install pytest

    mkdir -p /home/user/project/python
    mkdir -p /home/user/project/go/pb
    mkdir -p /home/user/project/proto
    mkdir -p /home/user/project/bin

    cat << 'EOF' > /home/user/project/python/generate.py
import json

def main():
    rules = ["/.env", "/.git/config", "/admin.php", "/wp-login.php"]
    with open("/home/user/project/rules.json", "w") as f:
        json.dump(rules, f)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/project/go/server_test.go
package main

import (
	"context"
	"reflect"
	"testing"
	"security/pb"
)

func TestAnalyzeLogs(t *testing.T) {
	server := &Server{}
	req := &pb.AnalyzeRequest{
		Logs: []string{
			"10.0.0.1 GET /index.html",
			"10.0.0.2 GET /.env",
			"10.0.0.1 POST /admin.php",
			"10.0.0.3 GET /images/logo.png",
			"10.0.0.2 POST /.env",
		},
	}

	resp, err := server.AnalyzeLogs(context.Background(), req)
	if err != nil {
		t.Fatalf("AnalyzeLogs failed: %v", err)
	}

	expected := []string{"10.0.0.1", "10.0.0.2"}
	if !reflect.DeepEqual(resp.MaliciousIps, expected) {
		t.Errorf("Expected %v, got %v", expected, resp.MaliciousIps)
	}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
