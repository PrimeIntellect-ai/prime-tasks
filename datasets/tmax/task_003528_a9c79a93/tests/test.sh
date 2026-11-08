#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_analyze_ast.go
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
        fmt.Fprintln(os.Stderr, "usage: check_analyze_ast <file>")
        os.Exit(2)
    }

    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
    if f.Name.Name != "main" {
        fmt.Fprintln(os.Stderr, "analyze.go must declare package main")
        os.Exit(1)
    }

    elfAlias := ""
    dotImport := false
    for _, imp := range f.Imports {
        path, err := strconv.Unquote(imp.Path.Value)
        if err != nil || path != "debug/elf" {
            continue
        }
        elfAlias = "elf"
        if imp.Name != nil {
            switch imp.Name.Name {
            case ".":
                dotImport = true
            case "_":
                elfAlias = ""
            default:
                elfAlias = imp.Name.Name
            }
        }
    }
    if elfAlias == "" && !dotImport {
        fmt.Fprintln(os.Stderr, "analyze.go must import debug/elf as a usable package")
        os.Exit(1)
    }

    hasELFOpen := false
    hasSectionAccess := false
    hasKeydataLiteral := false
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.BasicLit:
            if x.Kind == token.STRING {
                if value, err := strconv.Unquote(x.Value); err == nil && value == ".keydata" {
                    hasKeydataLiteral = true
                }
            }
        case *ast.SelectorExpr:
            if x.Sel.Name == "Section" || x.Sel.Name == "Sections" {
                hasSectionAccess = true
            }
        case *ast.CallExpr:
            switch fun := x.Fun.(type) {
            case *ast.SelectorExpr:
                if id, ok := fun.X.(*ast.Ident); ok && id.Name == elfAlias &&
                    (fun.Sel.Name == "Open" || fun.Sel.Name == "NewFile") {
                    hasELFOpen = true
                }
            case *ast.Ident:
                if dotImport && (fun.Name == "Open" || fun.Name == "NewFile") {
                    hasELFOpen = true
                }
            }
        }
        return true
    })

    if !hasELFOpen {
        fmt.Fprintln(os.Stderr, "analyze.go must call debug/elf.Open or debug/elf.NewFile")
        os.Exit(1)
    }
    if !hasSectionAccess || !hasKeydataLiteral {
        fmt.Fprintln(os.Stderr, "analyze.go must access the .keydata ELF section")
        os.Exit(1)
    }
}
GO_EOF

go build -o /tmp/check_analyze_ast /tmp/check_analyze_ast.go

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import os
import struct
import subprocess


def test_analyze_go_exists_and_runs(tmp_path):
    path = "/home/user/analyze.go"
    assert os.path.isfile(path), f"Missing file: {path}"

    subprocess.run(["/tmp/check_analyze_ast", path], check=True, timeout=20)

    executable = tmp_path / "analyze"
    subprocess.run(
        ["go", "build", "-o", str(executable), path],
        cwd="/home/user",
        check=True,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    nm = subprocess.run(
        ["go", "tool", "nm", str(executable)],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert "debug/elf." in nm.stdout, "Built program does not contain reachable debug/elf code"

    tracked = ["/home/user/password.txt", "/home/user/payload.bin"]
    originals = {}
    for item in tracked:
        if os.path.isfile(item):
            originals[item] = open(item, "rb").read()
        if os.path.lexists(item):
            os.unlink(item)

    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, "Unable to initialize inotify"
    wd = libc.inotify_add_watch(fd, b"/home/user/dropper.elf", 0x20)  # IN_OPEN
    assert wd >= 0, "Unable to watch dropper.elf"

    proc = None
    opened_dropper = False
    try:
        proc = subprocess.run(
            [str(executable)],
            cwd="/home/user",
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        try:
            events = os.read(fd, 65536)
        except BlockingIOError:
            events = b""
        offset = 0
        while offset + 16 <= len(events):
            event_wd, mask, cookie, name_len = struct.unpack_from("iIII", events, offset)
            if event_wd == wd and mask & 0x20:
                opened_dropper = True
            offset += 16 + name_len
    finally:
        os.close(fd)
        for item in tracked:
            if os.path.lexists(item):
                os.unlink(item)
            if item in originals:
                with open(item, "wb") as f:
                    f.write(originals[item])

    assert proc is not None and proc.returncode == 0, (
        f"analyze.go failed when executed: stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )
    assert opened_dropper, "The executed analyze.go program did not open /home/user/dropper.elf"


def test_password_txt_content():
    path = "/home/user/password.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read()

    expected_password = "V0rt3x_47"
    assert content == expected_password, f"Expected password.txt to contain '{expected_password}', but got '{content}'"


def test_payload_bin_extracted_and_hash_matches():
    bin_path = "/home/user/payload.bin"
    hash_path = "/home/user/payload.sha256"

    assert os.path.isfile(bin_path), f"Missing file: {bin_path}"
    assert os.path.isfile(hash_path), f"Missing file: {hash_path}"

    with open(hash_path, "r") as f:
        expected_hash_line = f.read().strip()
        expected_hash = expected_hash_line.split()[0]

    sha256 = hashlib.sha256()
    with open(bin_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)

    actual_hash = sha256.hexdigest()
    assert actual_hash == expected_hash, f"SHA256 of {bin_path} ({actual_hash}) does not match expected hash ({expected_hash})"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
