#!/bin/bash
set -u
mkdir -p /logs/verifier

verify() {
    local src=/home/user/workspace/processor.go
    local input=/home/user/data/raw_vectors.csv
    local output=/home/user/data/features.csv
    local original=/tmp/raw_vectors.original.$$
    local binary=/tmp/processor_test_bin.$$

    test -f "$src" || { echo "Go source file is missing: $src"; return 1; }
    cp "$input" "$original" || return 1
    trap 'cp "$original" /home/user/data/raw_vectors.csv 2>/dev/null || true; rm -f "$original" "$binary" /tmp/check_go_ast.$$ /tmp/check_go_ast_bin.$$' RETURN

    cat > /tmp/check_go_ast.$$ <<'GO_EOF'
package main

import (
    "fmt"
    "go/ast"
    "go/importer"
    "go/parser"
    "go/token"
    "go/types"
    "os"
)

func isChan(t types.Type) bool {
    if t == nil {
        return false
    }
    _, ok := t.Underlying().(*types.Chan)
    return ok
}

func main() {
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
    info := &types.Info{Types: make(map[ast.Expr]types.TypeAndValue)}
    conf := types.Config{Importer: importer.Default()}
    if _, err := conf.Check("submission", fset, []*ast.File{file}, info); err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    hasMain, hasGo, hasChan, hasSend, hasReceive := false, false, false, false, false
    ast.Inspect(file, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.FuncDecl:
            if x.Name.Name == "main" && x.Recv == nil {
                hasMain = true
            }
        case *ast.GoStmt:
            hasGo = true
        case *ast.ChanType:
            hasChan = true
        case *ast.SendStmt:
            if isChan(info.Types[x.Chan].Type) {
                hasSend = true
            }
        case *ast.UnaryExpr:
            if x.Op == token.ARROW && isChan(info.Types[x.X].Type) {
                hasReceive = true
            }
        case *ast.RangeStmt:
            if isChan(info.Types[x.X].Type) {
                hasReceive = true
            }
        }
        return true
    })
    if !hasMain || !hasGo || !hasChan || !hasSend || !hasReceive {
        fmt.Fprintf(os.Stderr, "source must define main and use goroutines plus channel send/receive operations (main=%v go=%v chan=%v send=%v receive=%v)\n", hasMain, hasGo, hasChan, hasSend, hasReceive)
        os.Exit(1)
    }
}
GO_EOF

    go build -o /tmp/check_go_ast_bin.$$ /tmp/check_go_ast.$$ || return 1
    /tmp/check_go_ast_bin.$$ "$src" || return 1

    (cd /home/user/workspace && go build -o "$binary" processor.go) || return 1

    cat > /tmp/test_final_state.py <<'PY_EOF'
import os
import csv
import json
import math
import pytest


def compute_expected_features(input_path):
    expected = []
    if not os.path.exists(input_path):
        return expected

    with open(input_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                id_val = int(row['ID'])
                vector_str = row['VectorData']
            except (KeyError, ValueError):
                continue

            vector_str = vector_str.replace('\\u03c0', '3.14159').replace('π', '3.14159')
            try:
                vector = json.loads(vector_str)
            except json.JSONDecodeError:
                continue

            if not isinstance(vector, list) or len(vector) < 3:
                continue

            try:
                vector = [float(x) for x in vector]
            except ValueError:
                continue

            l2_norm = math.sqrt(sum(x * x for x in vector))
            mean = sum(vector) / len(vector)
            variance = sum((x - mean) ** 2 for x in vector) / len(vector)
            expected.append({
                'ID': id_val,
                'L2Norm': f"{l2_norm:.4f}",
                'Variance': f"{variance:.4f}"
            })

    expected.sort(key=lambda x: x['ID'])
    return expected


def test_go_source_exists():
    src_path = "/home/user/workspace/processor.go"
    assert os.path.isfile(src_path), f"Go source file is missing: {src_path}"


def test_output_file_exists():
    out_path = "/home/user/data/features.csv"
    assert os.path.isfile(out_path), f"Output CSV file is missing: {out_path}"


def test_output_csv_content():
    in_path = "/home/user/data/raw_vectors.csv"
    out_path = "/home/user/data/features.csv"
    expected_data = compute_expected_features(in_path)

    with open(out_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("Output CSV is empty (missing header).")

        assert header == ['ID', 'L2Norm', 'Variance'], \
            f"CSV header is incorrect. Expected ['ID', 'L2Norm', 'Variance'], got {header}"

        actual_data = []
        for row in reader:
            if not row:
                continue
            assert len(row) == 3, f"Row does not have 3 columns: {row}"
            actual_data.append({
                'ID': int(row[0]),
                'L2Norm': row[1],
                'Variance': row[2]
            })

    assert len(actual_data) == len(expected_data), \
        f"Expected {len(expected_data)} valid rows, but found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual['ID'] == expected['ID'], \
            f"Row {i+1}: Expected ID {expected['ID']}, got {actual['ID']} (Rows must be sorted by ID)"
        assert actual['L2Norm'] == expected['L2Norm'], \
            f"Row {i+1} (ID {actual['ID']}): Expected L2Norm {expected['L2Norm']}, got {actual['L2Norm']}"
        assert actual['Variance'] == expected['Variance'], \
            f"Row {i+1} (ID {actual['ID']}): Expected Variance {expected['Variance']}, got {actual['Variance']}"
PY_EOF

    python3 - <<'PY_EOF'
import csv
import json
import random
import secrets

rng = random.SystemRandom()
ids = rng.sample(range(10000, 99999), 7)
rows = [
    (ids[0], json.dumps([rng.randint(-20, 20), rng.randint(-20, 20), rng.randint(-20, 20)])),
    (ids[1], json.dumps([rng.randint(-9, 9), rng.randint(-9, 9), rng.randint(-9, 9), rng.randint(-9, 9)])),
    (ids[2], r'[0.0, \u03c0, 4.0]'),
    (ids[3], json.dumps([1, 2])),
    (ids[4], 'corrupted_' + secrets.token_hex(8)),
    (ids[5], '[1, "bad", 3]'),
    (ids[6], json.dumps([-1, -1, -1, -1, -1])),
]
rng.shuffle(rows)
with open('/home/user/data/raw_vectors.csv', 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerow(['ID', 'VectorData'])
    writer.writerows(rows)
PY_EOF

    rm -f "$output"
    (cd /home/user/workspace && timeout 30 "$binary") || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py::test_output_csv_content -x --tb=short || return 1

    cp "$original" "$input" || return 1
    rm -f "$output"
    (cd /home/user/workspace && timeout 30 "$binary") || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

if verify 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
