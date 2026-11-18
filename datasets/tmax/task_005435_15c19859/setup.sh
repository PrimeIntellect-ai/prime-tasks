#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/oracle.go
package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

func main() {
	if len(os.Args) != 2 {
		return
	}
	input := os.Args[1]

	if !strings.HasPrefix(input, "GRAPH_UPDATE path=") {
		return
	}
	parts := strings.Split(input, " nodes=")
	if len(parts) != 2 {
		return
	}

	pathStr := strings.TrimPrefix(parts[0], "GRAPH_UPDATE path=")
	nodesStr := parts[1]

	// Parse nodes
	nodeStrs := strings.Split(nodesStr, ",")
	var nodes []int
	for _, ns := range nodeStrs {
		n, _ := strconv.Atoi(ns)
		nodes = append(nodes, n)
	}
	sort.Ints(nodes)
	var sortedNodeStrs []string
	for _, n := range nodes {
		sortedNodeStrs = append(sortedNodeStrs, strconv.Itoa(n))
	}
	nodesJoined := strings.Join(sortedNodeStrs, ", ")

	// Parse path
	pathNodes := strings.Split(pathStr, "->")
	var aliases []string
	for _, pn := range pathNodes {
		pn = strings.Trim(pn, "()")
		aliases = append(aliases, strings.ToLower(pn))
	}

	fmt.Println("BEGIN;")
	fmt.Printf("SELECT id FROM nodes WHERE id IN (%s) ORDER BY id FOR UPDATE;\n", nodesJoined)
	fmt.Println("WITH path_CTE AS (")

	var selectCols []string
	for _, a := range aliases {
		selectCols = append(selectCols, fmt.Sprintf("%s.id as %s_id", a, a))
	}
	fmt.Printf("  SELECT %s\n", strings.Join(selectCols, ", "))
	fmt.Printf("  FROM nodes %s\n", aliases[0])

	for i := 0; i < len(aliases)-1; i++ {
		fmt.Printf("  JOIN edges e%d ON %s.id = e%d.src\n", i+1, aliases[i], i+1)
		fmt.Printf("  JOIN nodes %s ON e%d.dst = %s.id\n", aliases[i+1], i+1, aliases[i+1])
	}

	fmt.Printf("  WHERE %s.id IN (%s)\n", aliases[0], nodesJoined)
	fmt.Println(")")
	fmt.Printf("UPDATE nodes SET path_count = path_count + 1 WHERE id IN (SELECT %s_id FROM path_CTE);\n", aliases[len(aliases)-1])
	fmt.Println("COMMIT;")
}
EOF

cd /tmp
go build -ldflags="-s -w" -o /app/sql_generator oracle.go
rm -f /tmp/oracle.go

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
