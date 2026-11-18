#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    # Create vendor directory
    mkdir -p /app/vendor/go-graph-etl
    cd /app/vendor/go-graph-etl
    go mod init go-graph-etl

    cat << 'EOF' > builder.go
package gographetl

import (
	"sync"
)

type Node struct {
	ID    string
	mu    sync.Mutex
	Edges []Edge
}

type Edge struct {
	To     string
	Weight int
}

type Graph struct {
	mu    sync.Mutex
	Nodes map[string]*Node
}

func NewGraph() *Graph {
	return &Graph{
		Nodes: make(map[string]*Node),
	}
}

func (g *Graph) GetNode(id string) *Node {
	g.mu.Lock()
	defer g.mu.Unlock()
	if n, ok := g.Nodes[id]; ok {
		return n
	}
	n := &Node{ID: id}
	g.Nodes[id] = n
	return n
}

func (g *Graph) AddEdge(from, to string, weight int) {
	n1 := g.GetNode(from)
	n2 := g.GetNode(to)
	n1.mu.Lock()
	n2.mu.Lock()
	n1.Edges = append(n1.Edges, Edge{To: to, Weight: weight})
	n2.mu.Unlock()
	n1.mu.Unlock()
}

type InputEdge struct {
	From   string `json:"from"`
	To     string `json:"to"`
	Weight int    `json:"weight"`
}

func BuildGraphConcurrent(edges []InputEdge) *Graph {
	g := NewGraph()
	var wg sync.WaitGroup
	for _, e := range edges {
		wg.Add(1)
		go func(edge InputEdge) {
			defer wg.Done()
			g.AddEdge(edge.From, edge.To, edge.Weight)
		}(e)
	}
	wg.Wait()
	return g
}
EOF

    # Create oracle
    mkdir -p /opt/oracle
    cd /opt/oracle
    cat << 'EOF' > etl_oracle.go
package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"sort"
)

type InputEdge struct {
	From   string `json:"from"`
	To     string `json:"to"`
	Weight int    `json:"weight"`
}

type Edge struct {
	To     string
	Weight int
}

func main() {
	if len(os.Args) < 2 {
		return
	}
	data, err := ioutil.ReadFile(os.Args[1])
	if err != nil {
		return
	}
	var edges []InputEdge
	if err := json.Unmarshal(data, &edges); err != nil {
		return
	}

	graph := make(map[string][]Edge)
	for _, e := range edges {
		graph[e.From] = append(graph[e.From], Edge{To: e.To, Weight: e.Weight})
	}

	var paths []string

	var dfs func(curr string, depth int, pathStr string, weightSum int)
	dfs = func(curr string, depth int, pathStr string, weightSum int) {
		if depth == 3 {
			if weightSum > 100 {
				paths = append(paths, pathStr)
			}
			return
		}
		for _, e := range graph[curr] {
			dfs(e.To, depth+1, pathStr+"->"+e.To, weightSum+e.Weight)
		}
	}

	for node := range graph {
		dfs(node, 0, node, 0)
	}

	sort.Strings(paths)
	if len(paths) > 10 {
		paths = paths[:10]
	}
	if paths == nil {
		paths = []string{}
	}

	out, _ := json.Marshal(paths)
	fmt.Println(string(out))
}
EOF
    go build -o etl_oracle etl_oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
