#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_pipeline_ast.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "path/filepath"
    "strconv"
    "strings"
)

func pkgCall(call *ast.CallExpr, aliases map[string]string, importPath, name string) bool {
    sel, ok := call.Fun.(*ast.SelectorExpr)
    if !ok || sel.Sel.Name != name {
        return false
    }
    id, ok := sel.X.(*ast.Ident)
    return ok && aliases[id.Name] == importPath
}

func main() {
    root := "/home/user/pipeline"
    foundMain := false
    foundGonumImport := false
    foundSQLiteImport := false
    foundNewDense := false
    foundMul := false
    foundSeededLocalRand := false
    foundNormFloat64 := false

    err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
        if err != nil {
            return err
        }
        if info.IsDir() {
            base := info.Name()
            if base == "vendor" || base == ".git" || strings.HasPrefix(base, ".cache") {
                return filepath.SkipDir
            }
            return nil
        }
        if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
            return nil
        }

        f, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
        if err != nil {
            return err
        }
        if f.Name.Name != "main" {
            return nil
        }
        foundMain = true

        aliases := map[string]string{}
        for _, imp := range f.Imports {
            p, err := strconv.Unquote(imp.Path.Value)
            if err != nil {
                continue
            }
            alias := filepath.Base(p)
            if imp.Name != nil {
                alias = imp.Name.Name
            }
            aliases[alias] = p
            if p == "gonum.org/v1/gonum/mat" {
                foundGonumImport = true
            }
            if p == "github.com/mattn/go-sqlite3" {
                foundSQLiteImport = true
            }
        }

        ast.Inspect(f, func(n ast.Node) bool {
            call, ok := n.(*ast.CallExpr)
            if !ok {
                return true
            }
            if pkgCall(call, aliases, "gonum.org/v1/gonum/mat", "NewDense") {
                foundNewDense = true
            }
            if sel, ok := call.Fun.(*ast.SelectorExpr); ok {
                if sel.Sel.Name == "Mul" {
                    foundMul = true
                }
                if sel.Sel.Name == "NormFloat64" {
                    foundNormFloat64 = true
                }
            }
            if pkgCall(call, aliases, "math/rand", "New") && len(call.Args) == 1 {
                inner, ok := call.Args[0].(*ast.CallExpr)
                if ok && pkgCall(inner, aliases, "math/rand", "NewSource") && len(inner.Args) == 1 {
                    if lit, ok := inner.Args[0].(*ast.BasicLit); ok && lit.Kind == token.INT {
                        if v, err := strconv.ParseInt(lit.Value, 0, 64); err == nil && v == 99 {
                            foundSeededLocalRand = true
                        }
                    }
                }
            }
            return true
        })
        return nil
    })
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    if !(foundMain && foundGonumImport && foundSQLiteImport && foundNewDense && foundMul && foundSeededLocalRand && foundNormFloat64) {
        fmt.Fprintf(os.Stderr, "implementation checks failed: main=%v gonum_import=%v sqlite_import=%v NewDense=%v Mul=%v seeded_local_rand=%v NormFloat64=%v\n",
            foundMain, foundGonumImport, foundSQLiteImport, foundNewDense, foundMul, foundSeededLocalRand, foundNormFloat64)
        os.Exit(1)
    }
}
GO_EOF

cat << 'GO_EOF' > /tmp/projection_oracle.go
package main

import (
    "bufio"
    "encoding/json"
    "fmt"
    "math/rand"
    "os"
)

type record struct {
    RecordID string    `json:"record_id"`
    Features []float64 `json:"features"`
}

type projection struct {
    RecordID string  `json:"record_id"`
    P1       float64 `json:"p1"`
    P2       float64 `json:"p2"`
    P3       float64 `json:"p3"`
}

func main() {
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    rng := rand.New(rand.NewSource(99))
    r := [8][3]float64{}
    for i := 0; i < 8; i++ {
        for j := 0; j < 3; j++ {
            r[i][j] = rng.NormFloat64()
        }
    }

    f, err := os.Open(os.Args[1])
    if err != nil {
        panic(err)
    }
    defer f.Close()

    out := []projection{}
    scanner := bufio.NewScanner(f)
    for scanner.Scan() {
        var rec record
        if json.Unmarshal(scanner.Bytes(), &rec) != nil || rec.RecordID == "" || len(rec.Features) != 8 {
            continue
        }
        p := [3]float64{}
        for i := 0; i < 8; i++ {
            for j := 0; j < 3; j++ {
                p[j] += rec.Features[i] * r[i][j]
            }
        }
        out = append(out, projection{rec.RecordID, p[0], p[1], p[2]})
    }
    if err := scanner.Err(); err != nil {
        panic(err)
    }
    if err := json.NewEncoder(os.Stdout).Encode(out); err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
}
GO_EOF

cat << 'PY_EOF' > /tmp/test_pipeline.py
import json
import math
import os
import random
import re
import sqlite3
import subprocess
import uuid

PIPELINE = "/home/user/pipeline"
SCRIPT = os.path.join(PIPELINE, "build_and_run.sh")
DB = os.path.join(PIPELINE, "results.db")
RAW = "/home/user/data/raw_metrics.jsonl"


def run(cmd, **kwargs):
    result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kwargs)
    assert result.returncode == 0, f"Command failed: {cmd}\n{result.stdout}"
    return result.stdout


def read_rows(db_path):
    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='projections';")
        assert cursor.fetchone() is not None, "Table 'projections' does not exist in the database."
        cursor.execute("SELECT record_id, p1, p2, p3 FROM projections ORDER BY record_id")
        return cursor.fetchall()
    finally:
        conn.close()


def test_original_final_state():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"The script {SCRIPT} is not executable."
    assert os.path.isfile(DB), f"The database {DB} does not exist."

    rows = read_rows(DB)
    rounded = [(rid, round(p1, 4), round(p2, 4), round(p3, 4)) for rid, p1, p2, p3 in rows]
    expected_rows = [
        ("rec_001", -0.1983, -1.4967, 1.9365),
        ("rec_002", -0.5358, 0.9022, 0.8413),
        ("rec_004", 0.1983, 1.4967, -1.9365),
        ("rec_005", 2.1332, 8.7618, -5.4093),
    ]
    assert len(rounded) == len(expected_rows), f"Expected {len(expected_rows)} rows, got {len(rounded)}."
    for i, (actual, expected) in enumerate(zip(rounded, expected_rows)):
        assert actual[0] == expected[0], f"Row {i+1}: expected ID {expected[0]}, got {actual[0]}."
        for j in range(1, 4):
            assert abs(actual[j] - expected[j]) <= 0.0001, f"Row {i+1}, projection {j}: expected {expected[j]}, got {actual[j]}."


def test_implementation_and_script():
    text = open(SCRIPT, encoding="utf-8").read()
    assert re.search(r"\bgo\s+mod\s+init\b", text), "build_and_run.sh does not initialize a Go module."
    assert re.search(r"\bgo\s+(?:get|mod\s+(?:tidy|download))\b", text), "build_and_run.sh does not install/resolve dependencies."
    assert re.search(r"\bgo\s+build\b", text), "build_and_run.sh does not build the Go program."
    assert re.search(r"CGO_ENABLED\s*=\s*1", text), "build_and_run.sh does not enable CGO."

    run(["go", "run", "/tmp/check_pipeline_ast.go"], timeout=120)
    deps = run(["go", "list", "-deps", "./..."], cwd=PIPELINE, timeout=120).splitlines()
    assert "gonum.org/v1/gonum/mat" in deps, "The Go implementation does not depend on gonum/mat."
    assert "github.com/mattn/go-sqlite3" in deps, "The Go implementation does not depend on go-sqlite3."


def test_pipeline_on_unseen_input():
    secure = random.SystemRandom()
    valid = []
    for _ in range(7):
        rid = "verify_" + uuid.uuid4().hex
        features = [secure.randint(-20000, 20000) / 137.0 for _ in range(8)]
        valid.append({"record_id": rid, "features": features})

    invalid = [
        {"record_id": "", "features": [1.0] * 8},
        {"record_id": "bad_short", "features": [1.0] * 7},
        {"record_id": "bad_long", "features": [1.0] * 9},
        {"record_id": "bad_missing_features"},
        {"features": [1.0] * 8},
        {"record_id": "bad_string", "features": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, "x"]},
        {"record_id": 123, "features": [1.0] * 8},
    ]
    records = valid + invalid
    secure.shuffle(records)
    with open(RAW, "w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record, separators=(",", ":")) + "\n")
        f.write("this is not json\n")

    expected_json = run(["go", "run", "/tmp/projection_oracle.go", RAW], timeout=120)
    expected = {r["record_id"]: (r["p1"], r["p2"], r["p3"]) for r in json.loads(expected_json)}
    assert set(expected) == {r["record_id"] for r in valid}

    if os.path.exists(DB):
        os.remove(DB)
    output = run([SCRIPT], cwd=PIPELINE, timeout=240, env={**os.environ, "CGO_ENABLED": "1"})
    assert os.path.isfile(DB), f"Pipeline execution did not create {DB}. Output:\n{output}"

    conn = sqlite3.connect(DB)
    try:
        info = conn.execute("PRAGMA table_info(projections)").fetchall()
        schema = [(row[1], row[2].upper(), row[5]) for row in info]
        assert schema == [
            ("record_id", "TEXT", 1),
            ("p1", "REAL", 0),
            ("p2", "REAL", 0),
            ("p3", "REAL", 0),
        ], f"Unexpected projections schema: {schema}"
        actual_rows = conn.execute("SELECT record_id, p1, p2, p3 FROM projections").fetchall()
    finally:
        conn.close()

    assert {row[0] for row in actual_rows} == set(expected), "Invalid records were retained or valid records were omitted."
    for rid, p1, p2, p3 in actual_rows:
        actual = (p1, p2, p3)
        wanted = expected[rid]
        for index, (a, e) in enumerate(zip(actual, wanted), 1):
            assert isinstance(a, float) and math.isfinite(a), f"{rid} p{index} is not a finite REAL value."
            assert math.isclose(a, e, rel_tol=1e-11, abs_tol=1e-9), f"{rid} p{index}: expected {e}, got {a}."
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_pipeline.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
