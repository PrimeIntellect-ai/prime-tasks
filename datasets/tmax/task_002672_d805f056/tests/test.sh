#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import time
import heapq
import shutil
import subprocess
import tempfile
import textwrap
import pytest


def get_expected_path():
    graph = {}
    csv_path = '/home/user/data/edges.csv'
    assert os.path.exists(csv_path), f"Data file {csv_path} is missing."

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            u = row['source']
            v = row['target']
            w = int(row['weight'])
            if u not in graph:
                graph[u] = []
            graph[u].append((v, w))

    start = "START_NODE"
    end = "END_NODE"

    pq = [(0, start)]
    distances = {start: 0}
    previous = {start: None}

    while pq:
        dist, current = heapq.heappop(pq)

        if current == end:
            break

        if dist > distances.get(current, float('inf')):
            continue

        for neighbor, weight in graph.get(current, []):
            new_dist = dist + weight
            if new_dist < distances.get(neighbor, float('inf')):
                distances[neighbor] = new_dist
                previous[neighbor] = (current, weight)
                heapq.heappush(pq, (new_dist, neighbor))

    if end not in distances:
        pytest.fail(f"No path found from {start} to {end} in the dataset.")

    path = []
    curr = end
    while curr != start:
        prev, w = previous[curr]
        path.append((curr, w))
        curr = prev
    path.reverse()

    result = [{"node": start, "cumulative_weight": 0}]
    cum_weight = 0
    for node, w in path:
        cum_weight += w
        result.append({"node": node, "cumulative_weight": cum_weight})

    return result


def test_analyze_script_execution_and_output():
    script_path = "/home/user/analyze.go"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."

    result_file = "/home/user/result.json"
    if os.path.exists(result_file):
        os.remove(result_file)

    start_time = time.time()
    proc = subprocess.run(
        ["go", "run", "analyze.go"],
        cwd="/home/user",
        capture_output=True,
        text=True
    )
    end_time = time.time()

    duration = end_time - start_time

    assert proc.returncode == 0, f"go run analyze.go failed with exit code {proc.returncode}.\nStderr: {proc.stderr}\nStdout: {proc.stdout}"
    assert duration < 1.0, f"Execution time {duration:.3f}s exceeded threshold of 1.0s. The graphdb package may not be properly optimized."

    assert os.path.exists(result_file), f"Output file {result_file} was not created."

    with open(result_file, "r") as f:
        try:
            actual_result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {result_file} is not valid JSON.")

    expected_result = get_expected_path()

    assert len(actual_result) == len(expected_result), f"Path length mismatch. Expected {len(expected_result)} nodes, got {len(actual_result)} nodes."

    for i, (actual, expected) in enumerate(zip(actual_result, expected_result)):
        assert actual.get("node") == expected["node"], f"Node mismatch at step {i}: expected {expected['node']}, got {actual.get('node')}."
        assert actual.get("cumulative_weight") == expected["cumulative_weight"], f"Cumulative weight mismatch at step {i} for node {expected['node']}: expected {expected['cumulative_weight']}, got {actual.get('cumulative_weight')}."


def test_graphdb_uses_edge_index():
    store_path = "/app/graphdb/store.go"
    assert os.path.exists(store_path), f"Graph store {store_path} is missing."

    ast_checker = r'''
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    f, err := parser.ParseFile(token.NewFileSet(), "/app/graphdb/store.go", nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    foundAdd, foundGet := false, false
    addUsesIndex, getUsesIndex, getRanges := false, false, false
    for _, decl := range f.Decls {
        fn, ok := decl.(*ast.FuncDecl)
        if !ok || fn.Recv == nil || fn.Body == nil {
            continue
        }
        switch fn.Name.Name {
        case "AddEdge":
            foundAdd = true
            ast.Inspect(fn.Body, func(n ast.Node) bool {
                if s, ok := n.(*ast.SelectorExpr); ok && s.Sel.Name == "edgeIndex" {
                    addUsesIndex = true
                }
                return true
            })
        case "GetEdges":
            foundGet = true
            ast.Inspect(fn.Body, func(n ast.Node) bool {
                if s, ok := n.(*ast.SelectorExpr); ok && s.Sel.Name == "edgeIndex" {
                    getUsesIndex = true
                }
                if _, ok := n.(*ast.RangeStmt); ok {
                    getRanges = true
                }
                return true
            })
        }
    }

    if !foundAdd || !foundGet || !addUsesIndex || !getUsesIndex || getRanges {
        fmt.Fprintf(os.Stderr, "AddEdge/GetEdges must maintain and directly use edgeIndex without a full-scan range loop (foundAdd=%v foundGet=%v addUsesIndex=%v getUsesIndex=%v getRanges=%v)\n", foundAdd, foundGet, addUsesIndex, getUsesIndex, getRanges)
        os.Exit(1)
    }
}
'''

    behavior_test = r'''
package graphdb

import "testing"

func TestVerifierEdgeIndexMaintenance(t *testing.T) {
    s := NewGraphStore()
    s.AddEdge("a", "b", 3)
    s.AddEdge("a", "c", 5)
    s.AddEdge("x", "y", 9)

    indexed := s.edgeIndex["a"]
    if len(indexed) != 2 || indexed[0].Target != "b" || indexed[0].Weight != 3 || indexed[1].Target != "c" || indexed[1].Weight != 5 {
        t.Fatalf("AddEdge did not maintain edgeIndex correctly: %#v", indexed)
    }

    got := s.GetEdges("a")
    if len(got) != 2 || got[0].Target != "b" || got[0].Weight != 3 || got[1].Target != "c" || got[1].Weight != 5 {
        t.Fatalf("GetEdges did not return indexed edges: %#v", got)
    }
    if got := s.GetEdges("missing"); len(got) != 0 {
        t.Fatalf("GetEdges returned edges for a missing node: %#v", got)
    }
}
'''

    checker_path = "/tmp/check_graphdb_ast.go"
    test_path = "/app/graphdb/verifier_index_test.go"
    try:
        with open(checker_path, "w") as f:
            f.write(ast_checker)
        proc = subprocess.run(["go", "run", checker_path], capture_output=True, text=True, timeout=30)
        assert proc.returncode == 0, f"graphdb index implementation check failed.\nStderr: {proc.stderr}\nStdout: {proc.stdout}"

        with open(test_path, "w") as f:
            f.write(behavior_test)
        proc = subprocess.run(["go", "test", "./..."], cwd="/app/graphdb", capture_output=True, text=True, timeout=30)
        assert proc.returncode == 0, f"graphdb edge-index behavior test failed.\nStderr: {proc.stderr}\nStdout: {proc.stdout}"
    finally:
        for path in (checker_path, test_path):
            if os.path.exists(path):
                os.remove(path)


def test_analyze_consumes_graphdb_shortest_path_result():
    analyze_path = "/home/user/analyze.go"
    data_path = "/home/user/data/edges.csv"
    result_path = "/home/user/result.json"

    assert os.path.exists(analyze_path), f"Script {analyze_path} does not exist."

    with open(data_path, "rb") as f:
        original_data = f.read()
    original_result = None
    if os.path.exists(result_path):
        with open(result_path, "rb") as f:
            original_result = f.read()

    with tempfile.TemporaryDirectory(prefix="graphdb_probe_") as root:
        app_dir = os.path.join(root, "app")
        graphdb_dir = os.path.join(root, "graphdb")
        os.makedirs(app_dir)
        os.makedirs(graphdb_dir)

        shutil.copy2(analyze_path, os.path.join(app_dir, "analyze.go"))

        with open(os.path.join(app_dir, "go.mod"), "w") as f:
            f.write(textwrap.dedent(f'''\
                module verifierprobe

                go 1.18

                require github.com/custom/graphdb v0.0.0
                replace github.com/custom/graphdb => {graphdb_dir}
            '''))

        with open(os.path.join(graphdb_dir, "go.mod"), "w") as f:
            f.write("module github.com/custom/graphdb\n\ngo 1.18\n")

        with open(os.path.join(graphdb_dir, "store.go"), "w") as f:
            f.write(r'''package graphdb

type Edge struct {
    Target string
    Weight int
}

type PathNode struct {
    Node string
    Weight int
}

type GraphStore struct{}

func NewGraphStore() *GraphStore { return &GraphStore{} }
func (s *GraphStore) AddEdge(source, target string, weight int) {}
func (s *GraphStore) GetEdges(nodeID string) []Edge { return nil }
func (s *GraphStore) ShortestPath(start, end string) []PathNode {
    return []PathNode{
        {Node: start, Weight: 0},
        {Node: "GRAPHDB_PROBE_NODE", Weight: 7},
        {Node: end, Weight: 11},
    }
}
''')

        try:
            with open(data_path, "w", newline="") as f:
                f.write("source,target,weight\nSTART_NODE,END_NODE,1\n")
            if os.path.exists(result_path):
                os.remove(result_path)

            env = os.environ.copy()
            env["GOWORK"] = "off"
            proc = subprocess.run(
                ["go", "run", "analyze.go"],
                cwd=app_dir,
                env=env,
                capture_output=True,
                text=True,
                timeout=30,
            )
            assert proc.returncode == 0, f"analyze.go failed against the graphdb API probe.\nStderr: {proc.stderr}\nStdout: {proc.stdout}"
            assert os.path.exists(result_path), "analyze.go did not create result.json during the graphdb API probe."

            with open(result_path, "r") as f:
                probe_result = json.load(f)

            expected = [
                {"node": "START_NODE", "cumulative_weight": 0},
                {"node": "GRAPHDB_PROBE_NODE", "cumulative_weight": 7},
                {"node": "END_NODE", "cumulative_weight": 18},
            ]
            assert len(probe_result) == len(expected), "analyze.go did not use the path returned by graphdb.ShortestPath."
            for i, (actual, wanted) in enumerate(zip(probe_result, expected)):
                assert actual.get("node") == wanted["node"], f"Probe node mismatch at step {i}; analyze.go must consume graphdb.ShortestPath output."
                assert actual.get("cumulative_weight") == wanted["cumulative_weight"], f"Probe cumulative weight mismatch at step {i}; analyze.go must consume graphdb.ShortestPath edge weights."
        finally:
            with open(data_path, "wb") as f:
                f.write(original_data)
            if original_result is None:
                if os.path.exists(result_path):
                    os.remove(result_path)
            else:
                with open(result_path, "wb") as f:
                    f.write(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
