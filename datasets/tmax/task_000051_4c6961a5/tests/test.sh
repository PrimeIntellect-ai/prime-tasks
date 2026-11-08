#!/bin/bash
set -u
mkdir -p /logs/verifier

run_checks() (
    set -e

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def is_valid_token(token: str) -> bool:
    h = 0
    p = 31
    m = int(1e9 + 9)
    p_pow = 1
    for char in token:
        h = (h + (ord(char) - ord('a') + 1) * p_pow) % m
        p_pow = (p_pow * p) % m
    return h % 1337 == 42

def test_static_library_built():
    lib_path = "/home/user/websec_port/libpolyhash.a"
    assert os.path.isfile(lib_path), f"The C static library was not built at {lib_path}"

def test_valid_tokens_file_exists():
    out_path = "/home/user/websec_port/valid_tokens.txt"
    assert os.path.isfile(out_path), f"The output file {out_path} was not created"

def test_valid_tokens_content():
    tokens_path = "/home/user/websec_port/tokens.txt"
    out_path = "/home/user/websec_port/valid_tokens.txt"

    assert os.path.isfile(tokens_path), f"Input file {tokens_path} is missing"
    assert os.path.isfile(out_path), f"Output file {out_path} is missing"

    expected_tokens = []
    with open(tokens_path, "r") as f:
        for line in f:
            token = line.strip()
            if token and is_valid_token(token):
                expected_tokens.append(token)

    expected_tokens.sort()

    actual_tokens = []
    with open(out_path, "r") as f:
        for line in f:
            token = line.strip()
            if token:
                actual_tokens.append(token)

    actual_tokens.sort()

    assert actual_tokens == expected_tokens, "The valid_tokens.txt file does not contain the correct valid tokens."
TEST_EOF

    # Preserve all original final-state assertions.
    python3 -m pytest /tmp/test_final_state.py -x --tb=short

    # Inspect the parsed Go syntax rather than trusting comments or textual output.
    cat << 'GO_EOF' > /tmp/check_websec_source.go
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
    if len(os.Args) != 2 {
        panic("usage: checker main.go")
    }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, parser.ParseComments)
    if err != nil {
        panic(err)
    }

    importsC := false
    for _, imp := range f.Imports {
        path, err := strconv.Unquote(imp.Path.Value)
        if err == nil && path == "C" {
            importsC = true
        }
    }

    comments := ""
    for _, group := range f.Comments {
        for _, comment := range group.List {
            comments += comment.Text + "\n"
        }
    }
    hasLinkDirective := strings.Contains(comments, "#cgo") &&
        strings.Contains(comments, "LDFLAGS:") &&
        (strings.Contains(comments, "-lpolyhash") || strings.Contains(comments, "libpolyhash.a"))

    hasValidateCall := false
    hasGoStatement := false
    hasChannelType := false
    hasChannelSend := false
    hasChannelReceive := false
    hasRange := false

    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.CallExpr:
            if sel, ok := x.Fun.(*ast.SelectorExpr); ok {
                if id, ok := sel.X.(*ast.Ident); ok && id.Name == "C" && sel.Sel.Name == "validate_token" {
                    hasValidateCall = true
                }
            }
            if id, ok := x.Fun.(*ast.Ident); ok && id.Name == "make" && len(x.Args) > 0 {
                if _, ok := x.Args[0].(*ast.ChanType); ok {
                    hasChannelType = true
                }
            }
        case *ast.GoStmt:
            hasGoStatement = true
        case *ast.ChanType:
            hasChannelType = true
        case *ast.SendStmt:
            hasChannelSend = true
        case *ast.UnaryExpr:
            if x.Op == token.ARROW {
                hasChannelReceive = true
            }
        case *ast.RangeStmt:
            hasRange = true
        }
        return true
    })

    checks := []struct {
        ok  bool
        msg string
    }{
        {importsC, "main.go must import C through cgo"},
        {hasLinkDirective, "main.go must have a cgo LDFLAGS directive linking libpolyhash"},
        {hasValidateCall, "main.go must call C.validate_token"},
        {hasGoStatement, "main.go must start at least one goroutine"},
        {hasChannelType, "main.go must create or declare a channel"},
        {hasChannelSend, "main.go must send work or results through a channel"},
        {hasChannelReceive || hasRange, "main.go must receive or range over channel work/results"},
    }
    for _, check := range checks {
        if !check.ok {
            fmt.Fprintln(os.Stderr, check.msg)
            os.Exit(1)
        }
    }
}
GO_EOF
    go run /tmp/check_websec_source.go /home/user/websec_port/main.go

    cd /home/user/websec_port
    make clean
    make
    test -f libpolyhash.a
    CGO_ENABLED=1 go build -o /tmp/websec_port_verifier_bin .
    test -x /tmp/websec_port_verifier_bin

    backup_dir=$(mktemp -d)
    cp -p tokens.txt "$backup_dir/tokens.txt"
    if [ -e valid_tokens.txt ]; then
        cp -p valid_tokens.txt "$backup_dir/valid_tokens.txt"
        had_output=1
    else
        had_output=0
    fi
    restore_files() {
        cp -p "$backup_dir/tokens.txt" /home/user/websec_port/tokens.txt
        if [ "$had_output" -eq 1 ]; then
            cp -p "$backup_dir/valid_tokens.txt" /home/user/websec_port/valid_tokens.txt
        else
            rm -f /home/user/websec_port/valid_tokens.txt
        fi
        rm -rf "$backup_dir"
    }
    trap restore_files EXIT

    # Replace the input with verifier-generated cases so a precomputed output cannot pass.
    python3 - << 'PY_EOF'
import random
import string

P = 31
M = 1_000_000_009

def valid(token):
    h = 0
    power = 1
    for ch in token:
        h = (h + (ord(ch) - ord('a') + 1) * power) % M
        power = (power * P) % M
    return h % 1337 == 42

rng = random.Random(908172635)
good, bad = [], []
while len(good) < 12 or len(bad) < 60:
    token = ''.join(rng.choice(string.ascii_lowercase) for _ in range(rng.randint(8, 28)))
    if valid(token):
        if len(good) < 12:
            good.append(token)
    elif len(bad) < 60:
        bad.append(token)

cases = good + bad
rng.shuffle(cases)
with open('/home/user/websec_port/tokens.txt', 'w') as f:
    for token in cases:
        f.write(token + '\n')
PY_EOF

    rm -f valid_tokens.txt
    timeout 30s /tmp/websec_port_verifier_bin
    test -f valid_tokens.txt

    python3 - << 'PY_EOF'
P = 31
M = 1_000_000_009

def valid(token):
    h = 0
    power = 1
    for ch in token:
        h = (h + (ord(ch) - ord('a') + 1) * power) % M
        power = (power * P) % M
    return h % 1337 == 42

with open('/home/user/websec_port/tokens.txt') as f:
    expected = sorted(line.strip() for line in f if line.strip() and valid(line.strip()))
with open('/home/user/websec_port/valid_tokens.txt') as f:
    actual = sorted(line.strip() for line in f if line.strip())

assert expected, 'Verifier-generated input unexpectedly had no valid tokens'
assert actual == expected, 'Compiled Go binary did not produce the correct output on verifier-generated tokens'
PY_EOF
)

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
