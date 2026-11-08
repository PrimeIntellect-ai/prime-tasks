#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg espeak-ng
    pip3 install pytest

    mkdir -p /app
    espeak-ng -w /app/dataset_memo.wav "Node Alpha connects to Node Beta. Node Beta connects to Node Gamma. Node Alpha connects to Node Delta. Node Gamma connects to Node Epsilon. Node Delta connects to Node Zeta."

    mkdir -p /home/user
    cat << 'EOF' > /home/user/graph_tool.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		return
	}
	data, _ := os.ReadFile(os.Args[1])
	edges := strings.Split(string(data), "\n")

	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		query := scanner.Text()
		results := make(map[string]bool)

		// BUG: Implicit cross join ignores actual graph topology
		for _, e1 := range edges {
			for _, e2 := range edges {
				if e1 == "" || e2 == "" { continue }
				p1 := strings.Split(e1, ",")
				p2 := strings.Split(e2, ",")
				// Bug: just adds everything
				if p1[0] == query || p2[0] == query || true {
					results[p1[1]] = true
					results[p2[1]] = true
				}
			}
		}

		var out []string
		for k := range results {
			out = append(out, k)
		}
		sort.Strings(out)
		fmt.Println(strings.Join(out, ","))
	}
}
EOF

    cat << 'EOF' > /app/oracle.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		return
	}
	data, _ := os.ReadFile(os.Args[1])
	edges := strings.Split(string(data), "\n")

	adj := make(map[string][]string)
	for _, e := range edges {
		if e == "" { continue }
		p := strings.Split(e, ",")
		if len(p) == 2 {
			adj[p[0]] = append(adj[p[0]], p[1])
		}
	}

	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		query := scanner.Text()
		results := make(map[string]bool)

		for _, n1 := range adj[query] {
			results[n1] = true
			for _, n2 := range adj[n1] {
				results[n2] = true
			}
		}

		var out []string
		for k := range results {
			out = append(out, k)
		}
		sort.Strings(out)
		fmt.Println(strings.Join(out, ","))
	}
}
EOF
    cd /app && go build -o oracle_graph_query oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
