#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl wget git golang-go
    pip3 install --default-timeout=100 pytest requests

    mkdir -p /app/vendored/graph-etl-engine
    cat << 'EOF' > /app/vendored/graph-etl-engine/transaction.go
package graphetl

import (
    "sync"
)

type Engine struct {
    nodes map[string]*Node
    mu    sync.RWMutex
}

type Node struct {
    ID    string
    Edges []string
    mu    sync.Mutex
}

func (e *Engine) AddEdge(from, to string) {
    e.mu.RLock()
    n1 := e.nodes[from]
    n2 := e.nodes[to]
    e.mu.RUnlock()

    // PERTURBATION: Locking without sorting IDs causes deadlocks under concurrency.
    n1.mu.Lock()
    n2.mu.Lock()

    n1.Edges = append(n1.Edges, to)

    n2.mu.Unlock()
    n1.mu.Unlock()
}
EOF

    cat << 'EOF' > /app/vendored/graph-etl-engine/go.mod
module graphetl

go 1.18
EOF

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/dump.nt
<Alice> <WORKS_IN> <Engineering> .
<Alice> <MANAGES> <Engineering> .
<Alice> <HAS_SALARY> "120000" .
<Charlie> <WORKS_IN> <Engineering> .
<Charlie> <HAS_SALARY> "80000" .
<Dave> <WORKS_IN> <Engineering> .
<Dave> <HAS_SALARY> "80000" .
<Bob> <WORKS_IN> <Sales> .
<Bob> <MANAGES> <Sales> .
<Bob> <HAS_SALARY> "90000" .
<Eve> <WORKS_IN> <Sales> .
<Eve> <HAS_SALARY> "50000" .
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
