#!/bin/bash
set +e
mkdir -p /logs/verifier

PARSER_DIR=/home/user/parser
ORIGINAL_PARSER=/tmp/verifier_original_parser.go
AUDIT_TEST="$PARSER_DIR/verifier_behavior_audit_test.go"
AUDIT_BACKUP=/tmp/verifier_behavior_audit_test.backup

cp "$PARSER_DIR/parser.go" "$ORIGINAL_PARSER" 2>/dev/null
if [ -e "$AUDIT_TEST" ]; then
    cp "$AUDIT_TEST" "$AUDIT_BACKUP"
fi

cleanup() {
    if [ -f "$ORIGINAL_PARSER" ]; then
        cp "$ORIGINAL_PARSER" "$PARSER_DIR/parser.go"
    fi
    if [ -f "$AUDIT_BACKUP" ]; then
        cp "$AUDIT_BACKUP" "$AUDIT_TEST"
    else
        rm -f "$AUDIT_TEST"
    fi
}
trap cleanup EXIT

cat << 'GO_EOF' > "$AUDIT_TEST"
package parser

import (
    "fmt"
    "testing"
)

func TestVerifierMalformedPayload(t *testing.T) {
    malformed := []byte{'Z', '3', 'R', '0', 20, 'x'}
    got, err := ParsePayload(malformed)
    if err == nil || err.Error() != "invalid length" {
        t.Fatalf("ParsePayload returned (%q, %v), want an invalid length error", got, err)
    }
}

func TestVerifierConcurrentProcessing(t *testing.T) {
    ParsedResults = make(map[string]string)
    payloads := make([][]byte, 128)
    expected := make([]string, 128)
    for i := range payloads {
        body := fmt.Sprintf("payload-%03d", i)
        expected[i] = body
        payloads[i] = append([]byte{'Z', '3', 'R', '0', byte(len(body))}, []byte(body)...)
    }

    ProcessConcurrent(payloads)

    if len(ParsedResults) != len(expected) {
        t.Fatalf("ParsedResults has %d entries, want %d", len(ParsedResults), len(expected))
    }
    for _, body := range expected {
        if ParsedResults[body] != "success" {
            t.Fatalf("missing successful result for %q", body)
        }
    }
}
GO_EOF

cat << 'GO_EOF' > /tmp/verifier_mutator.go
package main

import (
    "fmt"
    "go/ast"
    "go/format"
    "go/parser"
    "go/token"
    "os"
)

func donorBody(name string) *ast.BlockStmt {
    var source string
    switch name {
    case "parse":
        source = `package p
import "errors"
func replacement(data []byte) (string, error) {
    if len(data) < 5 { return "", errors.New("too short") }
    if string(data[0:4]) != "Z3R0" { return "", errors.New("bad magic") }
    length := int(data[4])
    payload := data[5:5+length]
    return string(payload), nil
}`
    case "concurrent":
        source = `package p
import "sync"
func replacement(payloads [][]byte) {
    var wg sync.WaitGroup
    for _, p := range payloads {
        wg.Add(1)
        go func(data []byte) {
            defer wg.Done()
            res, err := ParsePayload(data)
            if err == nil { ParsedResults[res] = "success" }
        }(p)
    }
    wg.Wait()
}`
    default:
        panic("unknown mutation")
    }
    f, err := parser.ParseFile(token.NewFileSet(), "donor.go", source, 0)
    if err != nil { panic(err) }
    for _, d := range f.Decls {
        if fn, ok := d.(*ast.FuncDecl); ok && fn.Name.Name == "replacement" {
            return fn.Body
        }
    }
    panic("replacement body not found")
}

func main() {
    if len(os.Args) != 3 {
        fmt.Fprintln(os.Stderr, "usage: mutator FILE parse|concurrent")
        os.Exit(2)
    }
    path, mode := os.Args[1], os.Args[2]
    target := "ParsePayload"
    if mode == "concurrent" { target = "ProcessConcurrent" }

    fset := token.NewFileSet()
    f, err := parser.ParseFile(fset, path, nil, parser.ParseComments)
    if err != nil { panic(err) }
    found := false
    for _, d := range f.Decls {
        if fn, ok := d.(*ast.FuncDecl); ok && fn.Name.Name == target {
            fn.Body = donorBody(mode)
            found = true
        }
    }
    if !found { panic("target function not found") }

    out, err := os.Create(path)
    if err != nil { panic(err) }
    if err := format.Node(out, fset, f); err != nil { panic(err) }
    if err := out.Close(); err != nil { panic(err) }
}
GO_EOF

go build -o /tmp/verifier_mutator /tmp/verifier_mutator.go
MUTATOR_BUILD=$?

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess

PARSER_DIR = "/home/user/parser"
PARSER_GO = os.path.join(PARSER_DIR, "parser.go")
ORIGINAL = "/tmp/verifier_original_parser.go"
MUTATOR = "/tmp/verifier_mutator"


def run_go_test(pattern=None):
    command = ["go", "test", "-race", "-count=1"]
    if pattern is not None:
        command.extend(["-run", pattern])
    return subprocess.run(
        command,
        cwd=PARSER_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )


def test_magic_txt():
    path = "/home/user/magic.txt"
    assert os.path.isfile(path), f"Expected file {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "Z3R0", f"Expected magic.txt to contain 'Z3R0', but got '{content}'."
    with open(path, "rb") as f:
        raw = f.read()
    assert raw == b"Z3R0", f"Expected magic.txt to contain exactly four bytes, got {raw!r}."


def test_parser_go_fixes():
    path = PARSER_GO
    assert os.path.isfile(path), f"Expected Go source file {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    assert "invalid length" in content, "Expected parser.go to return 'invalid length' error for bounds check."
    assert "Mutex" in content, "Expected parser.go to use sync.Mutex or sync.RWMutex."
    assert ".Lock()" in content, "Expected parser.go to lock the mutex."
    assert ".Unlock()" in content, "Expected parser.go to unlock the mutex."


def test_parser_test_go():
    path = os.path.join(PARSER_DIR, "parser_test.go")
    assert os.path.isfile(path), f"Expected test file {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "func TestParserRegression" in content, "Expected parser_test.go to contain func TestParserRegression(t *testing.T)."


def test_go_test_race_and_behavior():
    result = run_go_test()
    assert result.returncode == 0, f"'go test -race' failed with output:\n{result.stdout}\n{result.stderr}"


def mutate(mode):
    shutil.copyfile(ORIGINAL, PARSER_GO)
    result = subprocess.run(
        [MUTATOR, PARSER_GO, mode],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Could not create {mode} mutant:\n{result.stdout}\n{result.stderr}"


def test_agent_regression_test_detects_malformed_bug():
    try:
        mutate("parse")
        result = run_go_test("^TestParserRegression$")
        output = result.stdout + result.stderr
        assert result.returncode != 0, (
            "TestParserRegression passed when ParsePayload was restored to its out-of-bounds implementation."
        )
        assert "build failed" not in output.lower(), (
            "The malformed-input mutant was rejected only because the test did not compile:\n" + output
        )
    finally:
        shutil.copyfile(ORIGINAL, PARSER_GO)


def test_agent_regression_test_detects_race():
    try:
        mutate("concurrent")
        result = run_go_test("^TestParserRegression$")
        output = result.stdout + result.stderr
        assert result.returncode != 0 and "DATA RACE" in output, (
            "TestParserRegression did not expose the unsynchronized concurrent map writes under go test -race.\n"
            + output
        )
    finally:
        shutil.copyfile(ORIGINAL, PARSER_GO)
PY_EOF

if [ "$MUTATOR_BUILD" -eq 0 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
