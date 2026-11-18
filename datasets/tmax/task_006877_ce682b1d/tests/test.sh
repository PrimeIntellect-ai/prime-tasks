#!/bin/bash
set -u
mkdir -p /logs/verifier
pipeline=/home/user/ml_pipeline
structure_test="$pipeline/verifier_structure_test.go"
trap 'rm -f "$structure_test"' EXIT

cat <<'GO_EOF' > "$structure_test"
package main

import (
    "go/ast"
    "go/parser"
    "go/token"
    "path"
    "strconv"
    "testing"
)

func aliases(f *ast.File) map[string]string {
    out := map[string]string{}
    for _, imp := range f.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err != nil {
            continue
        }
        name := path.Base(p)
        if imp.Name != nil {
            name = imp.Name.Name
        }
        out[p] = name
    }
    return out
}

func TestVerifierStructure(t *testing.T) {
    fset := token.NewFileSet()
    mainFile, err := parser.ParseFile(fset, "main.go", nil, 0)
    if err != nil {
        t.Fatal(err)
    }
    testFile, err := parser.ParseFile(fset, "pipeline_test.go", nil, 0)
    if err != nil {
        t.Fatal(err)
    }

    imports := aliases(mainFile)
    matName, hasMat := imports["gonum.org/v1/gonum/mat"]
    statName, hasStat := imports["gonum.org/v1/gonum/stat"]
    if !hasMat || matName == "_" || matName == "." {
        t.Fatal("main.go must import and use gonum.org/v1/gonum/mat")
    }
    if !hasStat || statName == "_" || statName == "." {
        t.Fatal("main.go must import and use gonum.org/v1/gonum/stat")
    }

    usedMat := false
    usedCovarianceMatrix := false
    ast.Inspect(mainFile, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok {
            return true
        }
        sel, ok := call.Fun.(*ast.SelectorExpr)
        if !ok {
            return true
        }
        id, ok := sel.X.(*ast.Ident)
        if !ok {
            return true
        }
        if id.Name == matName {
            usedMat = true
        }
        if id.Name == statName && sel.Sel.Name == "CovarianceMatrix" {
            usedCovarianceMatrix = true
        }
        return true
    })
    if !usedMat {
        t.Fatal("main.go does not call the Gonum mat package")
    }
    if !usedCovarianceMatrix {
        t.Fatal("main.go must call stat.CovarianceMatrix")
    }

    var benchmark *ast.FuncDecl
    for _, decl := range testFile.Decls {
        if fn, ok := decl.(*ast.FuncDecl); ok && fn.Name.Name == "BenchmarkInference" {
            benchmark = fn
            break
        }
    }
    if benchmark == nil || benchmark.Body == nil {
        t.Fatal("BenchmarkInference is missing")
    }

    benchParam := ""
    if benchmark.Type.Params != nil && len(benchmark.Type.Params.List) > 0 {
        field := benchmark.Type.Params.List[0]
        star, ok := field.Type.(*ast.StarExpr)
        if ok {
            if sel, ok := star.X.(*ast.SelectorExpr); ok && sel.Sel.Name == "B" && len(field.Names) > 0 {
                benchParam = field.Names[0].Name
            }
        }
    }
    if benchParam == "" {
        t.Fatal("BenchmarkInference must accept *testing.B")
    }

    loopsBN := false
    ast.Inspect(benchmark.Body, func(n ast.Node) bool {
        loop, ok := n.(*ast.ForStmt)
        if !ok || loop.Cond == nil {
            return true
        }
        ast.Inspect(loop.Cond, func(m ast.Node) bool {
            sel, ok := m.(*ast.SelectorExpr)
            if !ok || sel.Sel.Name != "N" {
                return true
            }
            if id, ok := sel.X.(*ast.Ident); ok && id.Name == benchParam {
                loopsBN = true
            }
            return true
        })
        return true
    })
    if !loopsBN {
        t.Fatal("BenchmarkInference must loop using b.N")
    }

    hasHalf := false
    hasDotOperation := false
    ast.Inspect(testFile, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.BasicLit:
            if x.Kind == token.FLOAT || x.Kind == token.INT {
                if v, err := strconv.ParseFloat(x.Value, 64); err == nil && v == 0.5 {
                    hasHalf = true
                }
            }
        case *ast.BinaryExpr:
            if x.Op == token.MUL {
                hasDotOperation = true
            }
        case *ast.CallExpr:
            switch fun := x.Fun.(type) {
            case *ast.SelectorExpr:
                if fun.Sel.Name == "Dot" {
                    hasDotOperation = true
                }
            case *ast.Ident:
                if fun.Name == "Dot" || fun.Name == "dot" {
                    hasDotOperation = true
                }
            }
        }
        return true
    })
    if !hasHalf {
        t.Fatal("pipeline_test.go does not contain the required 0.5 weights")
    }
    if !hasDotOperation {
        t.Fatal("pipeline_test.go does not contain a dot-product operation")
    }
}
GO_EOF

cat <<'PY_EOF' > /tmp/verify_pipeline.py
import csv
import os
import re
import shutil
import subprocess
from pathlib import Path

PIPE = Path('/home/user/ml_pipeline')
FEATURES = Path('/home/user/features.csv')
COV = PIPE / 'covariance.csv'
BENCH = PIPE / 'benchmark.txt'


def run(cmd, *, check=True):
    return subprocess.run(
        cmd, cwd=PIPE, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, check=check, timeout=180
    )


def read_features(path):
    data = []
    with path.open(newline='') as f:
        for row in csv.reader(f):
            if row:
                assert len(row) == 3, 'features.csv must have exactly 3 columns'
                data.append([float(x) for x in row])
    return data


def covariance(data):
    n = len(data)
    assert n >= 2
    means = [sum(row[j] for row in data) / n for j in range(3)]
    return [[sum((row[i] - means[i]) * (row[j] - means[j]) for row in data) / (n - 1)
             for j in range(3)] for i in range(3)]


def check_covariance(data):
    assert COV.is_file(), f'{COV} is missing'
    lines = COV.read_text().strip().splitlines()
    assert len(lines) == 3, 'covariance.csv must contain exactly 3 rows'
    actual = []
    number = re.compile(r'^-?\d+\.\d{6}$')
    for line in lines:
        parts = line.split(',')
        assert len(parts) == 3, 'covariance.csv must contain exactly 3 columns'
        assert all(number.fullmatch(x) for x in parts), 'every covariance value must have exactly 6 decimal places'
        actual.append([float(x) for x in parts])
    expected = covariance(data)
    for i in range(3):
        for j in range(3):
            assert abs(actual[i][j] - expected[i][j]) < 1e-5, \
                f'covariance mismatch at ({i}, {j})'


for name in ('main.go', 'pipeline_test.go', 'go.mod'):
    assert (PIPE / name).is_file(), f'{PIPE / name} is missing'
assert FEATURES.is_file(), f'{FEATURES} is missing'
original = FEATURES.read_bytes()
original_data = read_features(FEATURES)
assert len(original_data) == 100, 'features.csv must contain exactly 100 rows'

module = run(['go', 'list', '-m']).stdout.strip()
assert module == 'ml_pipeline', f'Go module must be named ml_pipeline, got {module!r}'
run(['go', 'test', '-run', '^TestVerifierStructure$', '-count=1'])

live_benchmark = run(['go', 'test', '-run', '^$', '-bench', '^BenchmarkInference$', '-benchtime=10x', '-count=1'])
assert re.search(r'^BenchmarkInference(?:-\d+)?\s+\d+\s+', live_benchmark.stdout, re.MULTILINE), \
    'go test did not execute BenchmarkInference'

saved = BENCH.read_text() if BENCH.is_file() else ''
assert 'BenchmarkInference' in saved, f'{BENCH} does not contain BenchmarkInference output'
assert re.search(r'^BenchmarkInference(?:-\d+)?\s+\d+\s+.*ns/op', saved, re.MULTILINE), \
    'benchmark.txt is not raw Go benchmark output'
assert 'goos:' in saved and 'goarch:' in saved and ('PASS' in saved or '\nok\s' in saved), \
    'benchmark.txt is missing standard go test output'

backup = Path('/home/user/features.csv.verifier-backup')
if backup.exists():
    backup.unlink()
FEATURES.rename(backup)
try:
    missing = run(['go', 'test', '-run', '^$', '-bench', '^BenchmarkInference$', '-benchtime=1x', '-count=1'], check=False)
    assert missing.returncode != 0, 'BenchmarkInference does not actually read /home/user/features.csv'
finally:
    backup.rename(FEATURES)

challenge = []
for i in range(1, 101):
    challenge.append([
        i * 0.173 + (i % 7) * 0.031,
        ((i * 11) % 43) * 0.227 - i * 0.019,
        ((i * i + 5 * i) % 59) * 0.113 + i * 0.007,
    ])
with FEATURES.open('w', newline='') as f:
    writer = csv.writer(f, lineterminator='\n')
    writer.writerows([[f'{x:.9f}' for x in row] for row in challenge])
try:
    run(['go', 'run', '.'])
    check_covariance(challenge)
finally:
    FEATURES.write_bytes(original)

run(['go', 'run', '.'])
check_covariance(original_data)
PY_EOF

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
