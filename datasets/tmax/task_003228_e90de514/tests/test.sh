#!/bin/bash
mkdir -p /logs/verifier

cat <<'GO_EOF' > /tmp/check_svd_structure.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)

func main() {
    if len(os.Args) != 2 {
        fmt.Fprintln(os.Stderr, "usage: check_svd_structure <source.go>")
        os.Exit(1)
    }

    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, os.Args[1], nil, parser.AllErrors)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    constants := map[string]int64{}
    ast.Inspect(file, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.ValueSpec:
            for i, name := range x.Names {
                if i < len(x.Values) {
                    if v, ok := integer(x.Values[i], constants); ok {
                        constants[name.Name] = v
                    }
                }
            }
        case *ast.AssignStmt:
            for i, lhs := range x.Lhs {
                id, ok := lhs.(*ast.Ident)
                if ok && i < len(x.Rhs) {
                    if v, ok := integer(x.Rhs[i], constants); ok {
                        constants[id.Name] = v
                    }
                }
            }
        }
        return true
    })

    importedGonum := false
    for _, imp := range file.Imports {
        path, err := strconv.Unquote(imp.Path.Value)
        if err == nil && path == "gonum.org/v1/gonum/mat" {
            importedGonum = true
        }
    }

    selectors := map[string]bool{}
    seeds := map[int64]bool{}
    ast.Inspect(file, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.SelectorExpr:
            selectors[x.Sel.Name] = true
        case *ast.CallExpr:
            sel, ok := x.Fun.(*ast.SelectorExpr)
            if ok && sel.Sel.Name == "NewSource" && len(x.Args) == 1 {
                if v, ok := integer(x.Args[0], constants); ok {
                    seeds[v] = true
                }
            }
        }
        return true
    })

    launches := []int{}
    unknownLaunch := false
    var walk func(ast.Node, int)
    walk = func(node ast.Node, multiplier int) {
        if node == nil {
            return
        }
        ast.Inspect(node, func(n ast.Node) bool {
            if n == nil {
                return false
            }
            switch x := n.(type) {
            case *ast.ForStmt:
                iterations, ok := exactIterations(x, constants)
                if ok {
                    walk(x.Body, multiplier*iterations)
                } else {
                    walk(x.Body, -1)
                }
                return false
            case *ast.GoStmt:
                if multiplier < 0 {
                    unknownLaunch = true
                } else {
                    launches = append(launches, multiplier)
                }
                return false
            }
            return true
        })
    }
    walk(file, 1)

    fourWorkerLaunch := false
    standalone := 0
    for _, n := range launches {
        if n == 4 {
            fourWorkerLaunch = true
        }
        if n == 1 {
            standalone++
        }
    }
    if standalone >= 4 {
        fourWorkerLaunch = true
    }

    checks := []struct {
        ok  bool
        msg string
    }{
        {importedGonum, "source must import gonum.org/v1/gonum/mat"},
        {selectors["SVD"] && selectors["Factorize"], "source must use mat.SVD and perform SVD factorization"},
        {selectors["Float64"], "source must generate matrix entries with rand.Float64"},
        {selectors["Intn"], "source must bootstrap with rand.Intn"},
        {seeds[42] && seeds[99], "source must use deterministic random seeds 42 and 99"},
        {selectors["Add"] && selectors["Done"] && selectors["Wait"], "source must synchronize workers with a WaitGroup"},
        {fourWorkerLaunch, "source must launch four worker goroutines"},
        {!unknownLaunch || fourWorkerLaunch, "worker goroutine count must be statically bounded"},
    }

    failed := false
    for _, check := range checks {
        if !check.ok {
            fmt.Fprintln(os.Stderr, check.msg)
            failed = true
        }
    }
    if failed {
        os.Exit(1)
    }
}

func integer(expr ast.Expr, constants map[string]int64) (int64, bool) {
    switch x := expr.(type) {
    case *ast.BasicLit:
        if x.Kind != token.INT {
            return 0, false
        }
        v, err := strconv.ParseInt(x.Value, 0, 64)
        return v, err == nil
    case *ast.Ident:
        v, ok := constants[x.Name]
        return v, ok
    case *ast.ParenExpr:
        return integer(x.X, constants)
    }
    return 0, false
}

func exactIterations(loop *ast.ForStmt, constants map[string]int64) (int, bool) {
    init, ok := loop.Init.(*ast.AssignStmt)
    if !ok || len(init.Lhs) != 1 || len(init.Rhs) != 1 {
        return 0, false
    }
    variable, ok := init.Lhs[0].(*ast.Ident)
    if !ok {
        return 0, false
    }
    start, ok := integer(init.Rhs[0], constants)
    if !ok || start != 0 {
        return 0, false
    }

    cond, ok := loop.Cond.(*ast.BinaryExpr)
    if !ok {
        return 0, false
    }
    left, ok := cond.X.(*ast.Ident)
    if !ok || left.Name != variable.Name {
        return 0, false
    }
    bound, ok := integer(cond.Y, constants)
    if !ok {
        return 0, false
    }

    post, ok := loop.Post.(*ast.IncDecStmt)
    if !ok || post.Tok != token.INC {
        return 0, false
    }
    postVar, ok := post.X.(*ast.Ident)
    if !ok || postVar.Name != variable.Name {
        return 0, false
    }

    switch cond.Op {
    case token.LSS:
        if bound < 0 {
            return 0, false
        }
        return int(bound), true
    case token.LEQ:
        if bound < -1 {
            return 0, false
        }
        return int(bound + 1), true
    }
    return 0, false
}
GO_EOF

cat <<'PY_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess

import pytest

SOURCE = "/home/user/analyze_svd.go"
MOD = "/home/user/go.mod"
RESULTS = "/home/user/results.json"


def test_go_source_exists():
    """Check if the Go source file was created."""
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    assert os.path.getsize(SOURCE) > 0, f"{SOURCE} is empty."


def test_go_mod_exists():
    """Check if the Go module was initialized."""
    assert os.path.isfile(MOD), f"{MOD} does not exist."
    assert os.path.getsize(MOD) > 0, f"{MOD} is empty."


def test_required_go_structure():
    subprocess.run(
        ["/tmp/check_svd_structure", SOURCE],
        check=True,
        timeout=30,
        text=True,
    )


@pytest.fixture(scope="session")
def freshly_executed_submission():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    binary = "/tmp/analyze_svd_submission"
    if os.path.exists(binary):
        os.remove(binary)

    subprocess.run(
        ["go", "build", "-o", binary, "./analyze_svd.go"],
        cwd="/home/user",
        check=True,
        timeout=180,
        text=True,
    )
    subprocess.run(
        [binary],
        cwd="/home/user",
        check=True,
        timeout=240,
        text=True,
    )
    assert os.path.isfile(RESULTS), "Running the submitted Go program did not create results.json."
    return RESULTS


def test_results_json_exists_and_valid(freshly_executed_submission):
    """Check freshly generated results.json and its required values."""
    results_path = freshly_executed_submission
    assert os.path.isfile(results_path), f"{results_path} does not exist."

    with open(results_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{results_path} is not valid JSON.")

    expected_keys = {"mean", "ci_lower", "ci_upper"}
    assert set(data.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}. Found: {set(data.keys())}"

    expected_mean = 1588.6678226065487
    expected_ci_lower = 1007.6976251214044
    expected_ci_upper = 2507.0371465910714
    tolerance = 0.001

    assert isinstance(data["mean"], (int, float)) and math.isfinite(data["mean"])
    assert isinstance(data["ci_lower"], (int, float)) and math.isfinite(data["ci_lower"])
    assert isinstance(data["ci_upper"], (int, float)) and math.isfinite(data["ci_upper"])

    assert math.isclose(data["mean"], expected_mean, abs_tol=tolerance), \
        f"Expected mean to be approximately {expected_mean}, got {data['mean']}."
    assert math.isclose(data["ci_lower"], expected_ci_lower, abs_tol=tolerance), \
        f"Expected ci_lower to be approximately {expected_ci_lower}, got {data['ci_lower']}."
    assert math.isclose(data["ci_upper"], expected_ci_upper, abs_tol=tolerance), \
        f"Expected ci_upper to be approximately {expected_ci_upper}, got {data['ci_upper']}."
PY_EOF

if go build -o /tmp/check_svd_structure /tmp/check_svd_structure.go && \
   python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
