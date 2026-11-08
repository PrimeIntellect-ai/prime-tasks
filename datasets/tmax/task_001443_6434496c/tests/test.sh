#!/bin/bash
set +e
mkdir -p /logs/verifier

BACKUP_DIR=$(mktemp -d /tmp/dataset-backup.XXXXXX)
if [ -d /home/user/dataset ]; then
    cp -a /home/user/dataset "$BACKUP_DIR/dataset"
fi
cleanup() {
    if [ -d "$BACKUP_DIR/dataset" ]; then
        rm -rf /home/user/dataset
        cp -a "$BACKUP_DIR/dataset" /home/user/dataset
    fi
    rm -rf "$BACKUP_DIR" /tmp/analyzer_submission /tmp/check_analyzer.go /tmp/test_final_state.py
}
trap cleanup EXIT

cat << 'CHECK_EOF' > /tmp/check_analyzer.go
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
        os.Exit(1)
    }
    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    importsSyscall := false
    for _, imp := range file.Imports {
        path, err := strconv.Unquote(imp.Path.Value)
        if err == nil && path == "syscall" {
            importsSyscall = true
        }
    }

    hasGoStmt := false
    hasFlockWithExclusiveLock := false
    ast.Inspect(file, func(n ast.Node) bool {
        if _, ok := n.(*ast.GoStmt); ok {
            hasGoStmt = true
        }
        call, ok := n.(*ast.CallExpr)
        if !ok {
            return true
        }
        selector, ok := call.Fun.(*ast.SelectorExpr)
        if !ok || selector.Sel.Name != "Flock" {
            return true
        }
        callUsesLockEX := false
        for _, arg := range call.Args {
            ast.Inspect(arg, func(inner ast.Node) bool {
                if s, ok := inner.(*ast.SelectorExpr); ok && s.Sel.Name == "LOCK_EX" {
                    callUsesLockEX = true
                }
                if id, ok := inner.(*ast.Ident); ok && id.Name == "LOCK_EX" {
                    callUsesLockEX = true
                }
                return true
            })
        }
        if callUsesLockEX {
            hasFlockWithExclusiveLock = true
        }
        return true
    })

    if !importsSyscall || !hasGoStmt || !hasFlockWithExclusiveLock {
        fmt.Fprintf(os.Stderr, "required implementation features missing: syscall=%v goroutine=%v flock_LOCK_EX=%v\n", importsSyscall, hasGoStmt, hasFlockWithExclusiveLock)
        os.Exit(1)
    }
}
CHECK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import struct

MANIFEST_PATH = "/home/user/manifest.jsonl"
DATASET_DIR = "/home/user/dataset"

def test_analyzer_source_exists():
    assert os.path.isfile("/home/user/analyzer.go"), "Missing /home/user/analyzer.go"

def test_manifest_exists():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} does not exist."

def elf_entry_point(filepath):
    with open(filepath, "rb") as f:
        header = f.read(64)
    assert len(header) >= 32 and header[:4] == b"\x7fELF", f"Invalid ELF file: {filepath}"
    elf_class = header[4]
    data_encoding = header[5]
    assert elf_class in (1, 2), f"Unsupported ELF class in {filepath}"
    assert data_encoding in (1, 2), f"Unsupported ELF byte order in {filepath}"
    endian = "<" if data_encoding == 1 else ">"
    fmt = endian + ("I" if elf_class == 1 else "Q")
    return struct.unpack_from(fmt, header, 24)[0]

def test_manifest_contents_and_correctness():
    with open(MANIFEST_PATH, "r") as f:
        lines = [json.loads(l) for l in f if l.strip()]

    assert len(lines) == 6, f"Expected exactly 6 lines in manifest, got {len(lines)}."

    def get_entry(filepath):
        for line in lines:
            if line.get("filepath") == filepath:
                return line
        return None

    files_found = 0
    for root, _, files in os.walk(DATASET_DIR):
        for file in files:
            filepath = os.path.join(root, file)
            if not (file.endswith(".gcode") or file.endswith(".elf") or file.endswith(".wal")):
                continue

            files_found += 1
            entry = get_entry(filepath)
            assert entry is not None, f"Missing manifest entry for {filepath}"

            with open(filepath, "rb") as f_data:
                file_data = f_data.read()
                expected_sha256 = hashlib.sha256(file_data).hexdigest()
            assert entry.get("sha256") == expected_sha256, f"SHA256 mismatch for {filepath}"

            meta = entry.get("meta", {})
            assert isinstance(meta, dict), f"'meta' should be a dictionary for {filepath}"

            if file.endswith(".gcode"):
                assert entry.get("type") == "gcode", f"Expected type 'gcode' for {filepath}"
                max_z = None
                with open(filepath, "r") as f_gcode:
                    for line in f_gcode:
                        if line.startswith("G0") or line.startswith("G1"):
                            parts = line.split()
                            for part in parts:
                                if part.startswith("Z"):
                                    try:
                                        z_val = float(part[1:])
                                        if max_z is None or z_val > max_z:
                                            max_z = z_val
                                    except ValueError:
                                        pass
                assert "max_z" in meta, f"Missing 'max_z' in meta for {filepath}"
                assert meta["max_z"] == max_z, f"max_z mismatch for {filepath}. Expected {max_z}, got {meta['max_z']}"

            elif file.endswith(".wal"):
                assert entry.get("type") == "wal", f"Expected type 'wal' for {filepath}"
                with open(filepath, "rb") as f_wal:
                    header = f_wal.read(32)
                    if len(header) == 32:
                        page_size = struct.unpack(">I", header[8:12])[0]
                        file_size = os.path.getsize(filepath)
                        frames = (file_size - 32) // (24 + page_size)
                    else:
                        frames = 0
                assert "frames" in meta, f"Missing 'frames' in meta for {filepath}"
                assert meta["frames"] == frames, f"frames mismatch for {filepath}. Expected {frames}, got {meta['frames']}"

            elif file.endswith(".elf"):
                assert entry.get("type") == "elf", f"Expected type 'elf' for {filepath}"
                assert "entry_point" in meta, f"Missing 'entry_point' in meta for {filepath}"
                assert isinstance(meta["entry_point"], int), f"'entry_point' must be an integer for {filepath}"
                expected_entry = elf_entry_point(filepath)
                assert meta["entry_point"] == expected_entry, f"entry_point mismatch for {filepath}. Expected {expected_entry}, got {meta['entry_point']}"

    assert files_found == 6, f"Expected to find 6 relevant files in {DATASET_DIR}, found {files_found}."
TEST_EOF

# Randomize valid domain values before running the submitted program so a
# precomputed manifest cannot satisfy the behavioral checks.
python3 << 'MUTATE_EOF'
import os
import secrets
import struct

root = "/home/user/dataset"
for directory, _, files in os.walk(root):
    for name in files:
        path = os.path.join(directory, name)
        if name.endswith(".gcode"):
            value = 100000 + secrets.randbelow(900000) + secrets.randbelow(1000) / 1000.0
            with open(path, "a") as f:
                f.write(f"\nG1 X0 Y0 Z{value}\n")
        elif name.endswith(".elf"):
            with open(path, "r+b") as f:
                header = f.read(64)
                if len(header) < 32 or header[:4] != b"\x7fELF":
                    raise RuntimeError(f"invalid ELF: {path}")
                elf_class, data_encoding = header[4], header[5]
                endian = "<" if data_encoding == 1 else ">"
                fmt = endian + ("I" if elf_class == 1 else "Q")
                entry = 0x500000 + secrets.randbelow(0x100000)
                f.seek(24)
                f.write(struct.pack(fmt, entry))
        elif name.endswith(".wal"):
            page_size = secrets.choice([512, 1024, 2048, 4096])
            frames = 2 + secrets.randbelow(7)
            with open(path, "r+b") as f:
                header = bytearray(f.read(32))
                if len(header) != 32:
                    raise RuntimeError(f"invalid WAL: {path}")
                header[8:12] = struct.pack(">I", page_size)
                f.seek(0)
                f.write(header)
                f.truncate(32 + frames * (24 + page_size))
MUTATE_EOF
mutate_status=$?

result=0
if [ "$mutate_status" -eq 0 ] \
   && [ -f /home/user/analyzer.go ] \
   && go run /tmp/check_analyzer.go /home/user/analyzer.go \
   && go build -o /tmp/analyzer_submission /home/user/analyzer.go \
   && rm -f /home/user/manifest.jsonl \
   && (cd /home/user && timeout 30s /tmp/analyzer_submission) \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
    result=1
fi

echo "$result" > /logs/verifier/reward.txt
exit 0
