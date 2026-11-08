#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import ctypes
import fcntl
import io
import os
import random
import shutil
import struct
import subprocess
import tarfile
import time
import uuid
import zipfile


def test_extracted_files_exist():
    extracted_dir = "/home/user/organizer/extracted"
    expected_files = ["log_1.json", "log_2.json", "log_3.json"]

    for f in expected_files:
        file_path = os.path.join(extracted_dir, f)
        assert os.path.isfile(file_path), f"Expected extracted file {file_path} does not exist."


def test_extracted_files_match_nested_archive():
    archive = "/home/user/organizer/backups/data.zip"
    extracted_dir = "/home/user/organizer/extracted"
    expected_files = ["log_1.json", "log_2.json", "log_3.json"]

    with zipfile.ZipFile(archive) as outer:
        assert "internal.tar.gz" in outer.namelist()
        nested = outer.read("internal.tar.gz")

    with tarfile.open(fileobj=io.BytesIO(nested), mode="r:gz") as inner:
        for name in expected_files:
            member = inner.extractfile(name)
            assert member is not None, f"{name} is missing from internal.tar.gz"
            expected = member.read()
            with open(os.path.join(extracted_dir, name), "rb") as actual:
                assert actual.read() == expected, f"Extracted {name} does not match the archive"


def test_go_source_exists_and_contains_mechanics():
    go_file = "/home/user/organizer/process.go"
    assert os.path.isfile(go_file), f"Expected Go source file {go_file} does not exist."

    with open(go_file, "r") as f:
        content = f.read()

    assert "Flock" in content, "The Go program does not appear to use file locking (e.g., syscall.Flock)."
    assert "Rename" in content, "The Go program does not appear to use atomic rename (e.g., os.Rename)."


def test_summary_csv_content():
    csv_file = "/home/user/organizer/output/summary.csv"
    assert os.path.isfile(csv_file), f"Expected output file {csv_file} does not exist."

    expected_content = "id,action,user\n1,commit,alice\n2,build,bob\n3,push,charlie\n"

    with open(csv_file, "r") as f:
        actual_content = f.read()

    # Strip trailing newlines for comparison
    assert actual_content.strip() == expected_content.strip(), (
        f"Content of {csv_file} does not match expected output.\n"
        f"Expected:\n{expected_content.strip()}\n"
        f"Actual:\n{actual_content.strip()}"
    )


def test_program_executes_dynamic_conversion_with_lock_and_atomic_rename():
    root = "/home/user/organizer"
    source = os.path.join(root, "process.go")
    extracted = os.path.join(root, "extracted")
    output = os.path.join(root, "output")
    summary = os.path.join(output, "summary.csv")
    lock_path = os.path.join(output, "process.lock")

    # Check that Flock and Rename occur as actual Go call expressions, not only comments/strings.
    ast_checker = r'''
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
    if len(os.Args) != 2 { os.Exit(2) }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(1) }
    imports := map[string]string{}
    for _, imp := range f.Imports {
        p, _ := strconv.Unquote(imp.Path.Value)
        n := filepath.Base(p)
        if imp.Name != nil { n = imp.Name.Name }
        imports[n] = p
    }
    flock, rename := false, false
    ast.Inspect(f, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok { return true }
        sel, ok := call.Fun.(*ast.SelectorExpr)
        if !ok { return true }
        id, ok := sel.X.(*ast.Ident)
        if !ok { return true }
        p := imports[id.Name]
        if sel.Sel.Name == "Flock" && (p == "syscall" || p == "golang.org/x/sys/unix") { flock = true }
        if sel.Sel.Name == "Rename" && p == "os" { rename = true }
        return true
    })
    if !flock || !rename {
        fmt.Fprintf(os.Stderr, "actual calls missing: Flock=%v Rename=%v\n", flock, rename)
        os.Exit(1)
    }
}
'''
    checker_src = "/tmp/check_organizer_ast.go"
    checker_bin = "/tmp/check_organizer_ast"
    with open(checker_src, "w") as f:
        f.write(ast_checker)
    subprocess.run(["go", "build", "-o", checker_bin, checker_src], check=True, timeout=60)
    subprocess.run([checker_bin, source], check=True, timeout=10)

    program = "/tmp/organizer-process"
    subprocess.run(["go", "build", "-o", program, source], check=True, timeout=60)

    # Replace the extracted inputs with unpredictable valid data, so a fixed CSV cannot pass.
    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 9000), 3)
    token = uuid.uuid4().hex
    records = []
    for index, name in enumerate(["log_1.json", "log_2.json", "log_3.json"]):
        record = {
            "id": ids[index],
            "action": f"action_{token}_{index}",
            "user": f"user_{token}_{2-index}",
        }
        records.append(record)
        with open(os.path.join(extracted, name), "w") as f:
            import json
            json.dump(record, f)
            f.write("\n")

    expected_io = io.StringIO(newline="")
    writer = csv.writer(expected_io, lineterminator="\n")
    writer.writerow(["id", "action", "user"])
    for record in sorted(records, key=lambda r: r["id"]):
        writer.writerow([record["id"], record["action"], record["user"]])
    expected_csv = expected_io.getvalue()

    # Remove stale temp files, install a sentinel destination, and create a fresh lock inode.
    for name in os.listdir(output):
        path = os.path.join(output, name)
        if name == "summary.csv":
            continue
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    with open(summary, "w") as f:
        f.write("SENTINEL: destination must not change while lock is held\n")

    lock_file = open(lock_path, "a+")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

    libc = ctypes.CDLL(None, use_errno=True)
    inotify_fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert inotify_fd >= 0, os.strerror(ctypes.get_errno())
    IN_CREATE = 0x00000100
    IN_MOVED_TO = 0x00000080
    watch = libc.inotify_add_watch(inotify_fd, output.encode(), IN_CREATE | IN_MOVED_TO)
    assert watch >= 0, os.strerror(ctypes.get_errno())

    proc = None
    released = False
    try:
        proc = subprocess.Popen([program], cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        time.sleep(0.8)
        assert proc.poll() is None, "Program exited instead of waiting for the exclusive process.lock"
        with open(summary) as f:
            assert f.read().startswith("SENTINEL:"), "summary.csv changed before the held lock was released"

        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        released = True
        _, stderr = proc.communicate(timeout=15)
        assert proc.returncode == 0, f"Go program failed: {stderr.decode(errors='replace')}"

        events = []
        while True:
            try:
                data = os.read(inotify_fd, 65536)
            except BlockingIOError:
                break
            offset = 0
            while offset < len(data):
                _, mask, _, name_len = struct.unpack_from("iIII", data, offset)
                offset += 16
                raw_name = data[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
                events.append((mask, name))

        assert any((mask & IN_CREATE) and name not in ("summary.csv", "process.lock")
                   for mask, name in events), "Program did not create a temporary file in the output directory"
        assert any((mask & IN_MOVED_TO) and name == "summary.csv" for mask, name in events), (
            "summary.csv was not installed by an atomic rename into the output directory"
        )
        assert os.path.isfile(lock_path), "Dedicated process.lock was not present after execution"
        with open(summary, newline="") as f:
            actual = f.read()
        assert actual == expected_csv, f"Dynamic program output was incorrect. Expected:\n{expected_csv}\nActual:\n{actual}"
    finally:
        if not released:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()
        lock_file.close()
        os.close(inotify_fd)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
