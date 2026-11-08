#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/inspect_concurrent_test.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
    "strings"
)

func main() {
    path := os.Args[len(os.Args)-1]
    f, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
    if err != nil {
        fail("cannot parse main_test.go: %v", err)
    }

    constants := map[string]int{}
    ast.Inspect(f, func(n ast.Node) bool {
        d, ok := n.(*ast.GenDecl)
        if !ok || d.Tok != token.CONST {
            return true
        }
        for _, spec := range d.Specs {
            vs, ok := spec.(*ast.ValueSpec)
            if !ok {
                continue
            }
            for i, name := range vs.Names {
                if i < len(vs.Values) {
                    if v, ok := intValue(vs.Values[i], constants); ok {
                        constants[name.Name] = v
                    }
                }
            }
        }
        return true
    })

    hasResultPath := false
    ast.Inspect(f, func(n ast.Node) bool {
        lit, ok := n.(*ast.BasicLit)
        if ok && lit.Kind == token.STRING {
            value, _ := strconv.Unquote(lit.Value)
            if strings.HasSuffix(value, "result.txt") {
                hasResultPath = true
            }
        }
        return true
    })

    validTest := false
    for _, decl := range f.Decls {
        fn, ok := decl.(*ast.FuncDecl)
        if !ok || fn.Body == nil || !strings.HasPrefix(fn.Name.Name, "Test") {
            continue
        }

        hasHTTPTest := false
        hasChannel := false
        hasSend := false
        hasReceive := false
        hasStatusOK := false
        goCount := 0
        hasHundredGoLoop := false

        ast.Inspect(fn.Body, func(n ast.Node) bool {
            switch x := n.(type) {
            case *ast.SelectorExpr:
                if id, ok := x.X.(*ast.Ident); ok {
                    if id.Name == "httptest" && strings.HasPrefix(x.Sel.Name, "New") {
                        hasHTTPTest = true
                    }
                    if id.Name == "http" && x.Sel.Name == "StatusOK" {
                        hasStatusOK = true
                    }
                }
            case *ast.ChanType:
                hasChannel = true
            case *ast.SendStmt:
                hasSend = true
            case *ast.UnaryExpr:
                if x.Op == token.ARROW {
                    hasReceive = true
                }
            case *ast.GoStmt:
                goCount++
            case *ast.ForStmt:
                if loopIterations(x, constants) == 100 {
                    loopGoCount := 0
                    ast.Inspect(x.Body, func(child ast.Node) bool {
                        if _, ok := child.(*ast.GoStmt); ok {
                            loopGoCount++
                        }
                        return true
                    })
                    if loopGoCount == 1 {
                        hasHundredGoLoop = true
                    }
                }
            }
            return true
        })

        if hasHTTPTest && hasChannel && hasSend && hasReceive && hasStatusOK &&
            goCount == 1 && hasHundredGoLoop {
            validTest = true
        }
    }

    if !hasResultPath {
        fail("main_test.go does not reference result.txt")
    }
    if !validTest {
        fail("no Go test uses httptest, a send/receive channel, and exactly one goroutine launch inside a 100-iteration loop")
    }
}

func intValue(expr ast.Expr, constants map[string]int) (int, bool) {
    switch x := expr.(type) {
    case *ast.BasicLit:
        if x.Kind != token.INT {
            return 0, false
        }
        v, err := strconv.Atoi(x.Value)
        return v, err == nil
    case *ast.Ident:
        v, ok := constants[x.Name]
        return v, ok
    }
    return 0, false
}

func loopIterations(f *ast.ForStmt, constants map[string]int) int {
    init, ok := f.Init.(*ast.AssignStmt)
    if !ok || len(init.Lhs) != 1 || len(init.Rhs) != 1 {
        return -1
    }
    variable, ok := init.Lhs[0].(*ast.Ident)
    if !ok {
        return -1
    }
    start, ok := intValue(init.Rhs[0], constants)
    if !ok {
        return -1
    }

    cond, ok := f.Cond.(*ast.BinaryExpr)
    if !ok {
        return -1
    }
    left, ok := cond.X.(*ast.Ident)
    if !ok || left.Name != variable.Name {
        return -1
    }
    bound, ok := intValue(cond.Y, constants)
    if !ok {
        return -1
    }

    post, ok := f.Post.(*ast.IncDecStmt)
    if !ok || post.Tok != token.INC {
        return -1
    }
    postVar, ok := post.X.(*ast.Ident)
    if !ok || postVar.Name != variable.Name {
        return -1
    }

    switch cond.Op {
    case token.LSS:
        if bound <= start {
            return 0
        }
        return bound - start
    case token.LEQ:
        if bound < start {
            return 0
        }
        return bound - start + 1
    }
    return -1
}

func fail(format string, args ...interface{}) {
    fmt.Fprintf(os.Stderr, format+"\n", args...)
    os.Exit(1)
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pytest

WORKSPACE_DIR = "/home/user/workspace/auth"


def run_checked(command, **kwargs):
    try:
        return subprocess.run(command, check=True, capture_output=True, text=True, **kwargs)
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Command failed: {' '.join(command)}\nStdout: {e.stdout}\nStderr: {e.stderr}"
        )


def test_mock_s_exists():
    path = os.path.join(WORKSPACE_DIR, "mock.S")
    assert os.path.isfile(path), f"Assembly file {path} is missing."


def test_main_test_go_exists():
    path = os.path.join(WORKSPACE_DIR, "main_test.go")
    assert os.path.isfile(path), f"Test file {path} is missing."


def test_main_test_has_requested_structure():
    path = os.path.join(WORKSPACE_DIR, "main_test.go")
    run_checked(["go", "run", "/tmp/inspect_concurrent_test.go", "--", path])


def test_mock_is_linkable_function_returning_one():
    obj = "/tmp/verifier_mock.o"
    harness = "/tmp/verifier_mock_harness.c"
    binary = "/tmp/verifier_mock_harness"
    run_checked(["gcc", "-c", os.path.join(WORKSPACE_DIR, "mock.S"), "-o", obj])

    symbols = run_checked(["nm", "-g", "--defined-only", obj]).stdout
    assert re.search(r"(?:^|\n)[0-9A-Fa-f]+\s+T\s+check_sig(?:\n|$)", symbols), \
        "mock.S does not define check_sig as a global text/function symbol"

    with open(harness, "w") as f:
        f.write(r'''
extern int check_sig(char *msg);
int main(void) {
    char *samples[] = {"", "test", "unexpected-token-7f31", "a much longer token"};
    for (unsigned long i = 0; i < sizeof(samples) / sizeof(samples[0]); i++) {
        if (check_sig(samples[i]) != 1) return 1;
    }
    return 0;
}
''')
    run_checked(["gcc", harness, obj, "-o", binary])
    run_checked([binary])


def test_build_success():
    bin_path = os.path.join(WORKSPACE_DIR, "auth_bin")
    if os.path.exists(bin_path):
        os.remove(bin_path)
    run_checked(["go", "build", "-o", "auth_bin", "."], cwd=WORKSPACE_DIR)
    assert os.path.isfile(bin_path), "The built binary auth_bin was not found."


def test_run_submitted_tests_and_generate_result():
    result_path = os.path.join(WORKSPACE_DIR, "result.txt")
    if os.path.exists(result_path):
        os.remove(result_path)

    verifier_test = os.path.join(WORKSPACE_DIR, "zz_verifier_runtime_test.go")
    with open(verifier_test, "w") as f:
        f.write(r'''package main

import (
    "net/http"
    "net/http/httptest"
    "testing"
)

func TestVerifierRuntimeAuthHandler(t *testing.T) {
    tokens := []string{"", "test", "runtime-token-a91", "token with spaces"}
    for _, token := range tokens {
        req := httptest.NewRequest(http.MethodGet, "/auth?token="+token, nil)
        rec := httptest.NewRecorder()
        AuthHandler(rec, req)
        if rec.Code != http.StatusOK || rec.Body.String() != "OK" {
            t.Fatalf("AuthHandler returned status %d and body %q", rec.Code, rec.Body.String())
        }
    }
}
''')
    try:
        run_checked(["go", "test", "-count=1", "-timeout=30s", "."], cwd=WORKSPACE_DIR)
    finally:
        if os.path.exists(verifier_test):
            os.remove(verifier_test)

    assert os.path.isfile(result_path), f"Result file {result_path} was not created by go test."
    with open(result_path, "r") as f:
        content = f.read().strip()
    assert content == "100", f"Expected result.txt to contain '100', but found '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
