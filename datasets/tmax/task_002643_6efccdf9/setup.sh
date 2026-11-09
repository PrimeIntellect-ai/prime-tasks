#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git golang-go imagemagick fonts-dejavu-core
    pip3 install pytest flask

    # Create alert config image
    mkdir -p /app
    convert -size 400x200 xc:white -pointsize 24 -fill black -annotate +20+50 "Target SLA: 99.99%\nAuthToken: SRE-M0N-8821" /app/alert_config.png

    # Setup Git repository
    mkdir -p /home/user/monitor-stack
    cd /home/user/monitor-stack
    git init
    git config --global user.email "sre@example.com"
    git config --global user.name "SRE"

    # Create binary state file
    echo -n "encrypted_binary_data_here" > state.dat

    # Create secret config and commit
    echo "STATE_KEY=b7f9a2d4c6e8" > config.env
    git add config.env state.dat
    git commit -m "Initial commit with config"

    # Remove secret config and commit
    rm config.env
    git add config.env
    git commit -m "Remove secret config"

    # Create Go checker
    mkdir -p checker
    cat << 'EOF' > checker/main.go
package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
)

var graph = map[string][]string{
	"A": {"B"},
	"B": {"C"},
	"C": {"A"}, // Cycle
}

func resolveDependencies(node string) bool {
	// Missing visited map causes infinite recursion
	for _, dep := range graph[node] {
		resolveDependencies(dep)
	}
	return true
}

func main() {
	key := os.Getenv("STATE_KEY")
	if key == "" {
		panic("Missing STATE_KEY")
	}
	resolveDependencies("A")

	data := map[string]string{"status": "ok"}
	file, _ := json.MarshalIndent(data, "", " ")
	_ = ioutil.WriteFile("/tmp/health.json", file, 0644)
	fmt.Println("Health check complete")
}
EOF

    # Create Python dashboard
    mkdir -p dashboard
    cat << 'EOF' > dashboard/app.py
import json
from flask import Flask, request, jsonify
import math

app = Flask(__name__)

def calculate_variance(data):
    n = len(data)
    if n == 0: return 0
    sum_val = sum(data)
    sum_sq = sum(x*x for x in data)
    # Naive formula suffers from catastrophic cancellation
    return math.sqrt(sum_sq / n - (sum_val / n)**2)

@app.route('/api/status', methods=['GET'])
def status():
    # Missing auth check
    try:
        with open('/tmp/health.json') as f:
            health = json.load(f)
    except Exception:
        health = {}

    # Trigger numerical instability
    data = [1000000000.0, 1000000000.000001]
    var = calculate_variance(data)

    return jsonify({"health": health, "variance": var})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    git add checker dashboard
    git commit -m "Add checker and dashboard"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
