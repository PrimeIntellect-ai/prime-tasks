#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import ast
import base64
import os
import secrets
import shutil
import struct
import subprocess
from pathlib import Path

SOURCE = Path('/home/user/doc_converter.go')
INPUT_DIR = Path('/home/user/legacy_docs')
OUTPUT_DIR = Path('/home/user/docs_out')
BINARY = '/tmp/doc_converter_under_test'
AST_CHECKER = '/tmp/check_doc_converter_ast'

assert SOURCE.is_file(), '/home/user/doc_converter.go does not exist'

checker_source = r'''
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "path/filepath"
    "strconv"
)

func main() {
    if len(os.Args) != 2 {
        os.Exit(2)
    }

    file, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    lockAliases := map[string]bool{}
    dotLockImport := false
    for _, imp := range file.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err != nil {
            continue
        }
        if p != "syscall" && p != "golang.org/x/sys/unix" {
            continue
        }
        alias := filepath.Base(p)
        if imp.Name != nil {
            alias = imp.Name.Name
        }
        if alias == "." {
            dotLockImport = true
        } else if alias != "_" {
            lockAliases[alias] = true
        }
    }

    hasGoroutine := false
    hasFlock := false
    hasExclusive := false
    hasUnlock := false

    ast.Inspect(file, func(n ast.Node) bool {
        if _, ok := n.(*ast.GoStmt); ok {
            hasGoroutine = true
        }

        call, ok := n.(*ast.CallExpr)
        if !ok {
            return true
        }

        isFlock := false
        switch f := call.Fun.(type) {
        case *ast.SelectorExpr:
            if id, ok := f.X.(*ast.Ident); ok && lockAliases[id.Name] && f.Sel.Name == "Flock" {
                isFlock = true
            }
        case *ast.Ident:
            if dotLockImport && f.Name == "Flock" {
                isFlock = true
            }
        }
        if !isFlock {
            return true
        }

        hasFlock = true
        for _, arg := range call.Args {
            ast.Inspect(arg, func(x ast.Node) bool {
                switch v := x.(type) {
                case *ast.SelectorExpr:
                    if id, ok := v.X.(*ast.Ident); ok && lockAliases[id.Name] {
                        if v.Sel.Name == "LOCK_EX" {
                            hasExclusive = true
                        }
                        if v.Sel.Name == "LOCK_UN" {
                            hasUnlock = true
                        }
                    }
                case *ast.Ident:
                    if dotLockImport {
                        if v.Name == "LOCK_EX" {
                            hasExclusive = true
                        }
                        if v.Name == "LOCK_UN" {
                            hasUnlock = true
                        }
                    }
                }
                return true
            })
        }
        return true
    })

    if !hasGoroutine {
        fmt.Fprintln(os.Stderr, "program does not launch any goroutine")
        os.Exit(1)
    }
    if !hasFlock || !hasExclusive || !hasUnlock {
        fmt.Fprintln(os.Stderr, "program does not acquire and release an OS-level exclusive flock")
        os.Exit(1)
    }
}
'''
Path('/tmp/check_doc_converter_ast.go').write_text(checker_source, encoding='utf-8')

subprocess.run(
    ['go', 'build', '-o', AST_CHECKER, '/tmp/check_doc_converter_ast.go'],
    check=True,
    timeout=60,
)
subprocess.run([AST_CHECKER, str(SOURCE)], check=True, timeout=10)
subprocess.run(
    ['go', 'build', '-o', BINARY, str(SOURCE)],
    cwd='/home/user',
    check=True,
    timeout=60,
)


def write_bundles(records):
    shutil.rmtree(INPUT_DIR, ignore_errors=True)
    shutil.rmtree(OUTPUT_DIR, ignore_errors=True)
    INPUT_DIR.mkdir(parents=True)
    OUTPUT_DIR.mkdir(parents=True)
    for filename, relative_path, content in records:
        path_bytes = relative_path.encode('ascii')
        bundle = b'DOCB' + struct.pack('<I', len(path_bytes)) + path_bytes
        bundle += base64.b64encode(content.encode('utf-8'))
        (INPUT_DIR / filename).write_bytes(bundle)


def run_converter():
    subprocess.run([BINARY], cwd='/home/user', check=True, timeout=30)


def check_results(records):
    expected_lines = set()
    for filename, relative_path, expected_content in records:
        full_path = OUTPUT_DIR / relative_path
        assert full_path.is_file(), f'Output file {full_path} was not created'
        content = full_path.read_text(encoding='utf-8')
        assert content.strip() == expected_content.strip(), f'Content of {full_path} is incorrect'
        expected_lines.add(f'[SUCCESS] {filename} -> {relative_path}')

    log_path = OUTPUT_DIR / 'conversion.log'
    assert log_path.is_file(), f'Log file {log_path} was not created'
    lines = [line.strip() for line in log_path.read_text(encoding='utf-8').splitlines() if line.strip()]
    actual_lines = set(lines)
    assert len(lines) == len(records), f'Expected exactly {len(records)} lines in {log_path}, found {len(lines)}'
    assert actual_lines == expected_lines, (
        f'Log file contents do not match expected lines. '
        f'Missing: {expected_lines - actual_lines}, Unexpected: {actual_lines - expected_lines}'
    )


# Preserve and exercise all assertions made by the original verifier.
original_records = [
    ('doc1.bin', 'intro.md', '# Welcome to the docs'),
    ('doc2.bin', 'api/auth.md', '## Authentication API'),
    ('doc3.bin', 'setup/install.md', '## Installation Instructions'),
    ('doc4.bin', 'api/users/list.md', '## List Users API'),
]
write_bundles(original_records)
run_converter()
check_results(original_records)

# Exercise parsing, Base64 decoding, nested paths, and concurrent processing on
# unpredictable bundles that did not exist while the agent was running.
token = secrets.token_hex(12)
dynamic_records = []
for i in range(24):
    filename = f'bundle_{i:02d}_{token}.bin'
    if i % 3 == 0:
        relative_path = f'generated/{token}/page_{i:02d}.md'
    elif i % 3 == 1:
        relative_path = f'api/v{i}/{token}_entry_{i}.md'
    else:
        relative_path = f'guides/section_{i}/{token}.md'
    content = f'# Generated page {i}\n\nToken: {token}\nUnicode: café Ω\nValue: {secrets.token_hex(8)}'
    dynamic_records.append((filename, relative_path, content))

write_bundles(dynamic_records)
run_converter()
check_results(dynamic_records)
PY_EOF

result=0
python3 /tmp/verify_task.py && result=1
echo "$result" > /logs/verifier/reward.txt
