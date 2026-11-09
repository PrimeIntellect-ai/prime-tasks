#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq golang-go
pip3 install pytest

mkdir -p /app /verify/corpus/clean /verify/corpus/evil

cat << 'EOF' > /tmp/planner.go
package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
)

type Node struct {
	Op      string  `json:"operator"`
	Cost    int     `json:"est_cost"`
	Inputs  []Node  `json:"inputs,omitempty"`
}

func main() {
	bytes, _ := ioutil.ReadAll(os.Stdin)
	sum := sha256.Sum256(bytes)

	// Deterministic generation based on input hash
	cost1 := int(sum[0]) * 10
	cost2 := int(sum[1]) * 20
	cost3 := int(sum[2]) * 30

	root := Node{
		Op:   "Projection",
		Cost: cost1,
		Inputs: []Node{
			{
				Op:   "Filter",
				Cost: cost2,
				Inputs: []Node{
					{
						Op:   "Scan",
						Cost: cost3,
					},
				},
			},
		},
	}

	out, _ := json.MarshalIndent(root, "", "  ")
	fmt.Println(string(out))
}
EOF

cd /tmp && go build -ldflags="-s -w" -o /app/query_planner planner.go
rm /tmp/planner.go

echo -n "clean_query_1" > /verify/corpus/clean/q1.txt
echo -n "MATCH (n) RETURN n LIMIT 10" > /verify/corpus/clean/q2.txt

cat << 'EOF' > /tmp/gen_corpus.py
import hashlib
import os

clean_dir = "/verify/corpus/clean"
evil_dir = "/verify/corpus/evil"

evil_count = 0
clean_count = 0
for i in range(10000):
    text = f"query_{i}"
    h = hashlib.sha256(text.encode()).digest()
    cost = h[0]*10 + h[1]*20 + h[2]*30
    if cost > 5000 and evil_count < 10:
        with open(os.path.join(evil_dir, f"evil_{evil_count}.txt"), "w") as f:
            f.write(text)
        evil_count += 1
    elif cost <= 5000 and clean_count < 10:
        with open(os.path.join(clean_dir, f"clean_{clean_count}.txt"), "w") as f:
            f.write(text)
        clean_count += 1
EOF

python3 /tmp/gen_corpus.py
rm /tmp/gen_corpus.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
