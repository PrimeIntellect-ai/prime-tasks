#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import textwrap
import pytest


def test_minimal_hex_file():
    path = "/home/user/minimal_hex.txt"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_hex = "0080e03779c34143"
    assert content.lower() == expected_hex, f"Content of {path} is incorrect. Expected '{expected_hex}', got '{content}'."


def test_service_go_source():
    path = "/home/user/service.go"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "ctx.Done()" in content, f"File {path} does not seem to contain a check for ctx.Done()."

    # Parse the Go source so a mention in a comment is not sufficient. The call
    # must occur within a loop in processPayload.
    checker = r'''
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    path := os.Args[len(os.Args)-1]
    f, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    foundFunction := false
    foundDoneInLoop := false
    for _, decl := range f.Decls {
        fn, ok := decl.(*ast.FuncDecl)
        if !ok || fn.Name.Name != "processPayload" || fn.Body == nil {
            continue
        }
        foundFunction = true
        ast.Inspect(fn.Body, func(n ast.Node) bool {
            loop, ok := n.(*ast.ForStmt)
            if !ok {
                return true
            }
            ast.Inspect(loop.Body, func(inner ast.Node) bool {
                call, ok := inner.(*ast.CallExpr)
                if !ok {
                    return true
                }
                sel, ok := call.Fun.(*ast.SelectorExpr)
                if !ok || sel.Sel.Name != "Done" {
                    return true
                }
                id, ok := sel.X.(*ast.Ident)
                if ok && id.Name == "ctx" {
                    foundDoneInLoop = true
                }
                return true
            })
            return true
        })
    }

    if !foundFunction || !foundDoneInLoop {
        fmt.Fprintln(os.Stderr, "processPayload has no ctx.Done() call inside a loop")
        os.Exit(1)
    }
}
'''
    checker_path = "/tmp/check_ctx_done.go"
    with open(checker_path, "w") as f:
        f.write(checker)
    result = subprocess.run(
        ["go", "run", checker_path, "--", path],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        "service.go must contain an actual ctx.Done() call inside the "
        f"processPayload decay loop.\n{result.stdout}{result.stderr}"
    )


def test_source_handles_precision_loss_and_cancellation():
    source = "/home/user/service.go"
    with tempfile.TemporaryDirectory() as td:
        copied_source = os.path.join(td, "service.go")
        test_source = os.path.join(td, "service_test.go")
        shutil.copyfile(source, copied_source)

        with open(test_source, "w") as f:
            f.write(textwrap.dedent(r'''
                package main

                import (
                    "context"
                    "encoding/binary"
                    "math"
                    "sync"
                    "testing"
                    "time"
                )

                func runValue(ctx context.Context, value float64) <-chan struct{} {
                    data := make([]byte, 8)
                    binary.LittleEndian.PutUint64(data, math.Float64bits(value))
                    var wg sync.WaitGroup
                    wg.Add(1)
                    go processPayload(ctx, data, &wg)
                    done := make(chan struct{})
                    go func() {
                        wg.Wait()
                        close(done)
                    }()
                    return done
                }

                func TestPrecisionLossTerminates(t *testing.T) {
                    done := runValue(context.Background(), 1e16)
                    select {
                    case <-done:
                    case <-time.After(500 * time.Millisecond):
                        t.Fatal("processPayload did not terminate when subtraction made no progress")
                    }
                }

                func TestCancellationTerminates(t *testing.T) {
                    ctx, cancel := context.WithCancel(context.Background())
                    cancel()
                    // This value requires billions of iterations but subtraction
                    // still changes it, so a precision-only fix is insufficient.
                    done := runValue(ctx, 1e9)
                    select {
                    case <-done:
                    case <-time.After(500 * time.Millisecond):
                        t.Fatal("processPayload did not respect context cancellation")
                    }
                }
            '''))

        for name in ("TestPrecisionLossTerminates", "TestCancellationTerminates"):
            try:
                result = subprocess.run(
                    ["go", "test", "-run", f"^{name}$", "service.go", "service_test.go"],
                    cwd=td,
                    capture_output=True,
                    text=True,
                    timeout=8,
                    env={**os.environ, "GO111MODULE": "off"},
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Source-level behavioral test {name} timed out.")
            assert result.returncode == 0, (
                f"Source-level behavioral test {name} failed.\n"
                f"{result.stdout}\n{result.stderr}"
            )


def test_fixed_service_executable():
    path = "/home/user/fixed_service"
    assert os.path.exists(path), f"Executable {path} is missing. Did you compile the service?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_fixed_service_was_built_from_source():
    source = "/home/user/service.go"
    submitted = "/home/user/fixed_service"
    rebuilt = "/tmp/rebuilt_fixed_service"

    result = subprocess.run(
        ["go", "build", "-o", rebuilt, source],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"service.go does not compile:\n{result.stdout}\n{result.stderr}"

    with open(submitted, "rb") as f:
        submitted_bytes = f.read()
    with open(rebuilt, "rb") as f:
        rebuilt_bytes = f.read()
    assert submitted_bytes == rebuilt_bytes, (
        "/home/user/fixed_service is not the executable produced by building "
        "/home/user/service.go with the instructed go build command."
    )


def test_fixed_service_execution():
    executable = "/home/user/fixed_service"
    payload = "/home/user/payload.bin"

    assert os.path.exists(executable), "Fixed service executable not found."
    assert os.path.exists(payload), "Payload file not found."

    try:
        result = subprocess.run([executable, payload], capture_output=True, text=True, timeout=2)
    except subprocess.TimeoutExpired:
        pytest.fail("The fixed_service timed out. The infinite loop or goroutine leak is likely still present.")

    assert result.returncode == 0, f"fixed_service exited with code {result.returncode}, expected 0. Output: {result.stdout}\n{result.stderr}"
    assert "Success" in result.stdout, "fixed_service did not print 'Success'."
    assert "Watchdog" not in result.stdout, "fixed_service triggered the watchdog timeout."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
