#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_go_source.go
package main

import (
    "go/ast"
    "go/constant"
    "go/importer"
    "go/parser"
    "go/token"
    "go/types"
    "os"
)

func main() {
    if len(os.Args) < 2 {
        os.Exit(1)
    }

    fset := token.NewFileSet()
    files := make([]*ast.File, 0, len(os.Args)-1)
    for _, path := range os.Args[1:] {
        file, err := parser.ParseFile(fset, path, nil, 0)
        if err != nil || file.Name.Name != "main" {
            os.Exit(1)
        }
        files = append(files, file)
    }

    info := &types.Info{Types: make(map[ast.Expr]types.TypeAndValue)}
    conf := types.Config{Importer: importer.Default(), Error: func(error) {}}
    _, _ = conf.Check("submission", fset, files, info)

    hasMain := false
    hasThousand := false
    hasTimedLoopFunction := false

    for expr, tv := range info.Types {
        _ = expr
        if tv.Value != nil && constant.Compare(tv.Value, token.EQL, constant.MakeInt64(1000)) {
            hasThousand = true
        }
    }

    for _, file := range files {
        ast.Inspect(file, func(node ast.Node) bool {
            lit, ok := node.(*ast.BasicLit)
            if ok && lit.Kind == token.INT {
                if value := constant.MakeFromLiteral(lit.Value, token.INT, 0); value != nil &&
                    constant.Compare(value, token.EQL, constant.MakeInt64(1000)) {
                    hasThousand = true
                }
            }
            return true
        })

        for _, decl := range file.Decls {
            fn, ok := decl.(*ast.FuncDecl)
            if !ok || fn.Body == nil {
                continue
            }
            if fn.Name.Name == "main" {
                hasMain = true
            }

            hasLoop := false
            hasTiming := false
            ast.Inspect(fn.Body, func(node ast.Node) bool {
                switch n := node.(type) {
                case *ast.ForStmt, *ast.RangeStmt:
                    hasLoop = true
                case *ast.SelectorExpr:
                    switch n.Sel.Name {
                    case "Now", "Since", "Sub", "Nanoseconds", "Microseconds", "Milliseconds", "UnixNano":
                        hasTiming = true
                    }
                }
                return true
            })
            if hasLoop && hasTiming {
                hasTimedLoopFunction = true
            }
        }
    }

    if !hasMain || !hasThousand || !hasTimedLoopFunction {
        os.Exit(1)
    }
}
GO_EOF

go build -o /tmp/check_go_source /tmp/check_go_source.go

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import csv
import math
import shutil
import subprocess
import pytest

RESULTS_PATH = "/home/user/results.json"
VECTORS_PATH = "/home/user/vectors.csv"
QUERIES_PATH = "/home/user/queries.csv"


def compute_pearson_correlation(x, y):
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n

    cov = sum((a - mean_x) * (b - mean_y) for a, b in zip(x, y))
    var_x = sum((a - mean_x) ** 2 for a in x)
    var_y = sum((b - mean_y) ** 2 for b in y)

    if var_x == 0 or var_y == 0:
        return 0.0
    return cov / math.sqrt(var_x * var_y)


def compute_cosine_similarity(vec1, vec2):
    dot_product = sum(a * b for a, b in zip(vec1, vec2))
    norm_a = math.sqrt(sum(a ** 2 for a in vec1))
    norm_b = math.sqrt(sum(b ** 2 for b in vec2))

    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot_product / (norm_a * norm_b)


def find_go_packages():
    packages = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"go", ".cache", ".git", "vendor"}]
        go_files = sorted(
            os.path.join(root, name)
            for name in files
            if name.endswith(".go") and not name.endswith("_test.go")
        )
        main_files = []
        for path in go_files:
            try:
                with open(path, "r", encoding="utf-8") as handle:
                    text = handle.read()
            except (OSError, UnicodeDecodeError):
                continue
            if re.search(r"(?m)^\s*package\s+main\b", text):
                main_files.append(path)
        if main_files:
            packages.append(main_files)
    return packages


@pytest.fixture(scope="session", autouse=True)
def execute_go_submission():
    go = shutil.which("go") or "/usr/local/go/bin/go"
    assert os.path.isfile("/tmp/check_go_source"), "Go source checker could not be built"
    assert os.path.exists(go), "Go compiler is unavailable"

    packages = find_go_packages()
    assert packages, "No Go implementation using package main was found under /home/user"

    failures = []
    for files in packages:
        source_check = subprocess.run(
            ["/tmp/check_go_source", *files],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        if source_check.returncode != 0:
            failures.append(f"{os.path.dirname(files[0])}: missing a timed loop with a 1,000-run bound")
            continue

        try:
            os.remove(RESULTS_PATH)
        except FileNotFoundError:
            pass

        run = subprocess.run(
            [go, "run", *files],
            cwd=os.path.dirname(files[0]),
            env={**os.environ, "GO111MODULE": "off"},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        if run.returncode == 0 and os.path.isfile(RESULTS_PATH):
            return
        failures.append(
            f"{os.path.dirname(files[0])}: go run failed or did not create results.json: {run.stderr[-500:]}"
        )

    pytest.fail("No qualifying Go implementation executed successfully. " + " | ".join(failures))


@pytest.fixture(scope="module")
def expected_data():
    # Read vectors
    vectors = []
    f1_vals = []
    f2_vals = []

    with open(VECTORS_PATH, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            doc_id = row[0]
            features = [float(val) for val in row[1:]]
            vectors.append((doc_id, features))
            f1_vals.append(features[0])
            f2_vals.append(features[1])

    # Read queries
    query_1_features = None
    with open(QUERIES_PATH, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            if row[0] == "Query_1":
                query_1_features = [float(val) for val in row[1:]]
                break

    assert query_1_features is not None, "Query_1 not found in queries.csv"

    # Compute expected correlation
    expected_corr = compute_pearson_correlation(f1_vals, f2_vals)

    # Compute expected top 3
    similarities = []
    for doc_id, features in vectors:
        sim = compute_cosine_similarity(query_1_features, features)
        similarities.append((doc_id, sim))

    similarities.sort(key=lambda x: x[1], reverse=True)
    expected_top_3 = [x[0] for x in similarities[:3]]

    return {
        "correlation": expected_corr,
        "top_3": expected_top_3
    }


@pytest.fixture
def results_data():
    assert os.path.exists(RESULTS_PATH), f"Missing results file: {RESULTS_PATH}"
    with open(RESULTS_PATH, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON")
    return data


def test_results_format(results_data):
    """Test that results.json contains the expected keys."""
    expected_keys = {"correlation_F1_F2", "query_1_top_3", "benchmark_avg_ms"}
    missing_keys = expected_keys - set(results_data.keys())
    assert not missing_keys, f"results.json is missing keys: {missing_keys}"


def test_correlation_value(results_data, expected_data):
    """Test that the computed correlation is correct."""
    actual_corr = results_data.get("correlation_F1_F2")
    assert isinstance(actual_corr, (int, float)), "correlation_F1_F2 must be a number"

    expected_corr = expected_data["correlation"]
    # Check within 0.002 tolerance as per truth logic
    assert math.isclose(actual_corr, expected_corr, abs_tol=0.002), \
        f"Correlation mismatch. Expected ~{expected_corr:.3f}, got {actual_corr}"


def test_top_3_results(results_data, expected_data):
    """Test that the top 3 similar documents are correct."""
    actual_top_3 = results_data.get("query_1_top_3")
    assert isinstance(actual_top_3, list), "query_1_top_3 must be a list"
    assert len(actual_top_3) == 3, "query_1_top_3 must contain exactly 3 elements"

    expected_top_3 = expected_data["top_3"]
    assert actual_top_3 == expected_top_3, \
        f"Top 3 mismatch. Expected {expected_top_3}, got {actual_top_3}"


def test_benchmark_value(results_data):
    """Test that the benchmark value is a positive number."""
    benchmark_ms = results_data.get("benchmark_avg_ms")
    assert isinstance(benchmark_ms, (int, float)), "benchmark_avg_ms must be a number"
    assert benchmark_ms > 0, f"benchmark_avg_ms must be greater than 0, got {benchmark_ms}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
