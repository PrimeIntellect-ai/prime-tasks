#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_go_ast.go
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
    const filename = "/home/user/parse_logs.go"
    fset := token.NewFileSet()
    f, err := parser.ParseFile(fset, filename, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    aliases := map[string]string{}
    for _, imp := range f.Imports {
        path, _ := strconv.Unquote(imp.Path.Value)
        name := ""
        if imp.Name != nil {
            name = imp.Name.Name
        } else {
            switch path {
            case "compress/gzip": name = "gzip"
            case "bufio": name = "bufio"
            case "os": name = "os"
            case "syscall": name = "syscall"
            }
        }
        aliases[name] = path
    }
    if aliases["gzip"] != "compress/gzip" && !hasPath(aliases, "compress/gzip") {
        fail("compress/gzip is not imported")
    }
    if aliases["bufio"] != "bufio" && !hasPath(aliases, "bufio") {
        fail("bufio is not imported")
    }

    funcs := map[string]*ast.FuncDecl{}
    for _, d := range f.Decls {
        if fn, ok := d.(*ast.FuncDecl); ok && fn.Recv == nil {
            funcs[fn.Name.Name] = fn
        }
    }
    if funcs["main"] == nil {
        fail("main function is missing")
    }

    seen := map[string]bool{}
    queue := []string{"main"}
    gzipReader, bufioReader, bufioWriter := false, false, false
    flush, syncCall, renameCall := false, false, false

    for len(queue) > 0 {
        name := queue[0]
        queue = queue[1:]
        if seen[name] || funcs[name] == nil { continue }
        seen[name] = true
        ast.Inspect(funcs[name].Body, func(n ast.Node) bool {
            call, ok := n.(*ast.CallExpr)
            if !ok { return true }
            switch fun := call.Fun.(type) {
            case *ast.Ident:
                if funcs[fun.Name] != nil && !seen[fun.Name] {
                    queue = append(queue, fun.Name)
                }
            case *ast.SelectorExpr:
                if id, ok := fun.X.(*ast.Ident); ok {
                    path := aliases[id.Name]
                    switch {
                    case path == "compress/gzip" && fun.Sel.Name == "NewReader":
                        gzipReader = true
                    case path == "bufio" && (fun.Sel.Name == "NewScanner" || fun.Sel.Name == "NewReader" || fun.Sel.Name == "NewReaderSize"):
                        bufioReader = true
                    case path == "bufio" && (fun.Sel.Name == "NewWriter" || fun.Sel.Name == "NewWriterSize"):
                        bufioWriter = true
                    case (path == "os" || path == "syscall") && fun.Sel.Name == "Rename":
                        renameCall = true
                    case path == "syscall" && (fun.Sel.Name == "Fsync" || fun.Sel.Name == "Fdatasync"):
                        syncCall = true
                    }
                }
                if fun.Sel.Name == "Flush" { flush = true }
                if fun.Sel.Name == "Sync" { syncCall = true }
            }
            return true
        })
    }

    if !gzipReader { fail("reachable code does not create a gzip reader") }
    if !bufioReader { fail("reachable code does not create a buffered streaming reader/scanner") }
    if bufioWriter && !flush { fail("reachable code creates a buffered writer but does not flush it") }
    if !syncCall { fail("reachable code does not sync the temporary file") }
    if !renameCall { fail("reachable code does not call os.Rename or syscall.Rename") }
}

func hasPath(m map[string]string, want string) bool {
    for _, p := range m { if p == want { return true } }
    return false
}

func fail(s string) {
    fmt.Fprintln(os.Stderr, s)
    os.Exit(1)
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import errno
import gzip
import json
import os
import random
import re
import struct
import subprocess
import uuid

SOURCE = "/home/user/raw_data/system_logs.gz"
DEST_DIR = "/home/user/project_xray"
DEST = DEST_DIR + "/fatal.log"
SCRIPT = "/home/user/parse_logs.go"
BINARY = "/tmp/parse_logs_submission"


def test_fatal_log_content():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    assert os.path.isfile(DEST), f"Destination file {DEST} was not created."

    expected_lines = []
    with gzip.open(SOURCE, 'rt') as f:
        for line in f:
            try:
                data = json.loads(line)
                if data.get("project") == "x-ray" and data.get("level") == "FATAL":
                    expected_lines.append(line)
            except json.JSONDecodeError:
                continue

    with open(DEST, 'r') as f:
        actual_lines = f.readlines()

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {DEST}, but found {len(actual_lines)}."
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in {DEST} does not match the expected raw JSON string."


def test_go_script_atomic_rename():
    assert os.path.isfile(SCRIPT), f"Go script {SCRIPT} is missing."
    with open(SCRIPT, 'r') as f:
        content = f.read()

    # Retain the original assertion and add an AST-based reachable-code check.
    assert re.search(r'\b(os|syscall)\.Rename\b', content), f"The Go script {SCRIPT} does not appear to use os.Rename or syscall.Rename for atomic writing."
    subprocess.run(["go", "run", "/tmp/check_go_ast.go"], check=True, timeout=60)


def _read_events(fd):
    events = []
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            break
        if not data:
            break
        pos = 0
        while pos < len(data):
            wd, mask, cookie, length = struct.unpack_from("iIII", data, pos)
            pos += 16
            raw_name = data[pos:pos + length]
            pos += length
            name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
            events.append((mask, cookie, name))
    return events


def test_execute_go_artifact_and_observe_atomic_replacement():
    subprocess.run(["go", "build", "-o", BINARY, SCRIPT], check=True, timeout=60)

    source_backup = open(SOURCE, "rb").read()
    dest_existed = os.path.exists(DEST)
    dest_backup = open(DEST, "rb").read() if dest_existed else None

    token = uuid.uuid4().hex
    records = [
        (' { "timestamp" : "T1", "project" : "x-ray", "level" : "FATAL", "message" : "' + token + '-one" }\n').encode(),
        ('{"timestamp":"T2","project":"other","level":"FATAL","message":"' + token + '-skip"}\n').encode(),
        b'not-json-at-all\n',
        ('{"message":"' + token + '-two","level":"FATAL","project":"x-ray","timestamp":"T3"}\n').encode(),
        ('{"timestamp":"T4","project":"x-ray","level":"INFO","message":"' + token + '-skip"}\n').encode(),
    ]
    random.shuffle(records)
    expected = b"".join(line for line in records if _is_match(line))

    libc = ctypes.CDLL(None, use_errno=True)
    inotify_init1 = libc.inotify_init1
    inotify_init1.argtypes = [ctypes.c_int]
    inotify_init1.restype = ctypes.c_int
    inotify_add_watch = libc.inotify_add_watch
    inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    inotify_add_watch.restype = ctypes.c_int

    IN_NONBLOCK = os.O_NONBLOCK
    IN_CREATE = 0x00000100
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    WATCH_MASK = IN_CREATE | IN_MOVED_FROM | IN_MOVED_TO

    fd = -1
    try:
        with gzip.open(SOURCE, "wb") as f:
            for line in records:
                f.write(line)
        if os.path.exists(DEST):
            os.unlink(DEST)

        fd = inotify_init1(IN_NONBLOCK)
        assert fd >= 0, os.strerror(ctypes.get_errno())
        wd = inotify_add_watch(fd, DEST_DIR.encode(), WATCH_MASK)
        assert wd >= 0, os.strerror(ctypes.get_errno())

        subprocess.run([BINARY], cwd="/home/user", check=True, timeout=60)
        events = _read_events(fd)

        assert os.path.isfile(DEST), "Executing the submitted Go program did not create fatal.log"
        assert open(DEST, "rb").read() == expected, "The executed Go program did not derive the correct raw output from the verifier's input"

        fatal_creates = [e for e in events if e[0] & IN_CREATE and e[2] == "fatal.log"]
        assert not fatal_creates, "fatal.log was opened/created directly rather than installed solely by rename"

        creates = {(cookie, name) for mask, cookie, name in events if mask & IN_CREATE and name != "fatal.log"}
        moved_from = {(cookie, name) for mask, cookie, name in events if mask & IN_MOVED_FROM and name != "fatal.log"}
        moved_to = [(cookie, name) for mask, cookie, name in events if mask & IN_MOVED_TO and name == "fatal.log"]
        assert moved_to, "No atomic rename into fatal.log was observed while executing the Go program"
        cookie = moved_to[-1][0]
        old_names = [name for c, name in moved_from if c == cookie]
        assert old_names, "fatal.log was not renamed from a temporary file in the destination directory"
        assert any(any(name == created_name for _, created_name in creates) for name in old_names), "The renamed temporary file was not created in the destination directory during this run"
        assert all(not os.path.exists(os.path.join(DEST_DIR, name)) for name in old_names), "A temporary output file was left behind"
    finally:
        if fd >= 0:
            os.close(fd)
        with open(SOURCE, "wb") as f:
            f.write(source_backup)
        if dest_existed:
            with open(DEST, "wb") as f:
                f.write(dest_backup)
        elif os.path.exists(DEST):
            os.unlink(DEST)


def _is_match(line):
    try:
        obj = json.loads(line)
        return obj.get("project") == "x-ray" and obj.get("level") == "FATAL"
    except (ValueError, UnicodeDecodeError):
        return False
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
