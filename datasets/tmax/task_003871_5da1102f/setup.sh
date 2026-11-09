#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go binutils
    pip3 install pytest pandas

    mkdir -p /app/data
    mkdir -p /home/user

    # Generate data
    cat << 'EOF' > /app/data/generate.py
import json
import random

random.seed(42)

users = [f"U{i:04d}" for i in range(10000)]
products = [f"P{i:03d}" for i in range(500)]

with open('/app/data/nodes.jsonl', 'w') as f:
    for u in users:
        f.write(json.dumps({"id": u, "type": "User"}) + '\n')
    for p in products:
        f.write(json.dumps({"id": p, "type": "Product"}) + '\n')

with open('/app/data/edges.jsonl', 'w') as f:
    for _ in range(50000):
        u1 = random.choice(users)
        u2 = random.choice(users)
        if u1 != u2:
            f.write(json.dumps({"src": u1, "dst": u2, "rel": "KNOWS"}) + '\n')

    for _ in range(20000):
        u = random.choice(users)
        p = random.choice(products)
        f.write(json.dumps({"src": u, "dst": p, "rel": "BOUGHT"}) + '\n')
EOF
    python3 /app/data/generate.py

    # Create reference engine in Go
    cat << 'EOF' > /app/ref_engine.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
)

type Edge struct {
	Src string `json:"src"`
	Dst string `json:"dst"`
	Rel string `json:"rel"`
}

func main() {
	edgeFile, err := os.Open("edges.jsonl")
	if err != nil {
		panic(err)
	}
	defer edgeFile.Close()

	var knows []Edge
	var bought []Edge

	scanner := bufio.NewScanner(edgeFile)
	for scanner.Scan() {
		var e Edge
		json.Unmarshal(scanner.Bytes(), &e)
		if e.Rel == "KNOWS" {
			knows = append(knows, e)
		} else if e.Rel == "BOUGHT" {
			bought = append(bought, e)
		}
	}

	prodUsers := make(map[string][]string)
	for _, e := range bought {
		prodUsers[e.Dst] = append(prodUsers[e.Dst], e.Src)
	}

	var results []string
	unique := make(map[string]bool)

	for p, users := range prodUsers {
		for i := 0; i < len(users); i++ {
			for j := i + 1; j < len(users); j++ {
				u1 := users[i]
				u2 := users[j]
				if u1 == u2 {
					continue
				}
				if u1 > u2 {
					u1, u2 = u2, u1
				}

				// Linear scan for KNOWS to make it slow
				knew := false
				for _, k := range knows {
					if (k.Src == u1 && k.Dst == u2) || (k.Src == u2 && k.Dst == u1) {
						knew = true
						break
					}
				}

				if knew {
					res := fmt.Sprintf("%s,%s,%s", p, u1, u2)
					if !unique[res] {
						unique[res] = true
						results = append(results, res)
					}
				}
			}
		}
	}

	sort.Strings(results)

	out, _ := os.Create("results.csv")
	defer out.Close()
	out.WriteString("User1,User2,Product\n")
	for _, r := range results {
		parts := strings.Split(r, ",")
		out.WriteString(fmt.Sprintf("%s,%s,%s\n", parts[1], parts[2], parts[0]))
	}
}
EOF

    cd /app
    go build -o ref_engine ref_engine.go
    strip ref_engine
    chmod +x ref_engine
    rm ref_engine.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
