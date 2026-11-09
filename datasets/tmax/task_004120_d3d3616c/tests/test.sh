#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_resolver_ast.go
package main

import (
    "bytes"
    "fmt"
    "go/ast"
    "go/parser"
    "go/printer"
    "go/token"
    "os"
    "strings"
)

func main() {
    if len(os.Args) != 2 {
        fmt.Fprintln(os.Stderr, "usage: check_resolver_ast <resolver.go>")
        os.Exit(2)
    }

    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    hasGoStatement := false
    hasExclusiveFlockCall := false

    ast.Inspect(file, func(node ast.Node) bool {
        switch n := node.(type) {
        case *ast.GoStmt:
            hasGoStatement = true
        case *ast.CallExpr:
            selector, ok := n.Fun.(*ast.SelectorExpr)
            if !ok || selector.Sel.Name != "Flock" {
                return true
            }
            pkg, ok := selector.X.(*ast.Ident)
            if !ok || pkg.Name != "syscall" || len(n.Args) < 2 {
                return true
            }
            var rendered bytes.Buffer
            if err := printer.Fprint(&rendered, fset, n.Args[1]); err == nil && strings.Contains(rendered.String(), "LOCK_EX") {
                hasExclusiveFlockCall = true
            }
        }
        return true
    })

    if !hasGoStatement {
        fmt.Fprintln(os.Stderr, "resolver.go contains no actual go statement")
        os.Exit(1)
    }
    if !hasExclusiveFlockCall {
        fmt.Fprintln(os.Stderr, "resolver.go contains no actual syscall.Flock call using LOCK_EX")
        os.Exit(1)
    }
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import fcntl
import os
import pathlib
import pwd
import secrets
import shutil
import subprocess
import tempfile
import time

LOGS_DIR = "/home/user/logs"
RESOLVER_GO = "/home/user/resolver.go"
RECOVERY_TXT = os.path.join(LOGS_DIR, "full_recovery.txt")

def test_resolver_go_exists_and_uses_flock():
    assert os.path.isfile(RESOLVER_GO), f"File {RESOLVER_GO} does not exist."
    with open(RESOLVER_GO, "r") as f:
        content = f.read()
    assert "syscall.Flock" in content, f"syscall.Flock is not used in {RESOLVER_GO}."

def test_full_recovery_file_exists_and_has_50_lines():
    assert os.path.isfile(RECOVERY_TXT), f"Output file {RECOVERY_TXT} does not exist."
    with open(RECOVERY_TXT, "r") as f:
        lines = f.readlines()

    # Filter out empty lines if any, though the task expects exactly 50
    non_empty_lines = [line for line in lines if line.strip()]
    assert len(non_empty_lines) == 50, f"Expected 50 lines in {RECOVERY_TXT}, found {len(non_empty_lines)}."

def test_full_recovery_content():
    # Verify that all expected log entries are present in the recovery file
    with open(RECOVERY_TXT, "r") as f:
        content = f.read()

    for i in range(1, 51):
        num_str = f"{i:03d}"
        expected_entry = f"CRITICAL_LOG_ENTRY_{num_str}: System state stable at timestamp {num_str}000"
        assert expected_entry in content, f"Missing expected log entry in {RECOVERY_TXT}: {expected_entry}"

def test_part_files_are_gone():
    part_files = [f for f in os.listdir(LOGS_DIR) if f.endswith(".part")]
    assert len(part_files) == 0, f"Found unexpected .part files in {LOGS_DIR}: {part_files}"

def test_done_files_exist_and_correct_count():
    done_files = [f for f in os.listdir(LOGS_DIR) if f.endswith(".done")]
    assert len(done_files) == 50, f"Expected 50 .done files in {LOGS_DIR}, found {len(done_files)}."

    # Ensure specific files exist
    for i in range(1, 51):
        num_str = f"{i:03d}"
        expected_file = f"syslog_{num_str}.done"
        assert expected_file in done_files, f"Missing expected file {expected_file} in {LOGS_DIR}."

def test_symlink_loop_still_exists():
    symlink_path = os.path.join(LOGS_DIR, "loop_link")
    assert os.path.islink(symlink_path), f"Symlink {symlink_path} does not exist or is not a symlink."
    assert os.readlink(symlink_path) == ".", f"Symlink {symlink_path} does not point to '.'."

def test_source_compiles_and_contains_real_concurrency_and_flock_calls():
    subprocess.run(
        ["go", "run", "/tmp/check_resolver_ast.go", RESOLVER_GO],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    subprocess.run(
        ["go", "build", "-o", "/tmp/resolver_verified", RESOLVER_GO],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_compiled_resolver_on_fresh_unknown_fixture_with_lock_contention():
    assert os.path.isfile("/tmp/resolver_verified")

    parent = os.path.dirname(LOGS_DIR)
    backup = tempfile.mkdtemp(prefix="logs-verifier-backup-", dir=parent)
    backup_logs = os.path.join(backup, "logs")
    outside = tempfile.mkdtemp(prefix="resolver-outside-", dir="/tmp")
    process = None
    lock_file = None

    try:
        os.rename(LOGS_DIR, backup_logs)
        os.makedirs(LOGS_DIR)
        os.makedirs(os.path.join(LOGS_DIR, "nested", "deeper"))
        os.makedirs(os.path.join(LOGS_DIR, "other"))

        token = secrets.token_hex(16)
        expected_lines = []
        expected_done = set()
        for i in range(96):
            if i % 3 == 0:
                rel_dir = ""
            elif i % 3 == 1:
                rel_dir = "nested"
            else:
                rel_dir = os.path.join("nested", "deeper")
            name = f"fragment_{i:03d}_{token}.part"
            rel_part = os.path.join(rel_dir, name) if rel_dir else name
            line = f"DYNAMIC_RECOVERY_{token}_{i:03d}_{secrets.token_hex(12)}"
            expected_lines.append(line)
            with open(os.path.join(LOGS_DIR, rel_part), "w", encoding="utf-8") as f:
                f.write(line + "\n")
            expected_done.add(str(pathlib.Path(rel_part).with_suffix(".done")))

        # Files without .part must not be processed.
        with open(os.path.join(LOGS_DIR, "other", "leave_me.txt"), "w", encoding="utf-8") as f:
            f.write("NOT_A_FRAGMENT\n")

        # Both a recursive directory link and a .part link to an external file
        # must be ignored rather than followed or renamed.
        os.symlink(".", os.path.join(LOGS_DIR, "loop_link"))
        trap_target = os.path.join(outside, "external_trap.txt")
        with open(trap_target, "w", encoding="utf-8") as f:
            f.write("SYMLINK_TRAP_MUST_NOT_APPEAR\n")
        trap_link = os.path.join(LOGS_DIR, "nested", "symlink_trap.part")
        os.symlink(trap_target, trap_link)

        user = pwd.getpwnam("user")
        for root, dirs, files in os.walk(LOGS_DIR):
            os.chown(root, user.pw_uid, user.pw_gid)
            os.chmod(root, 0o777)
            for name in files:
                path = os.path.join(root, name)
                if not os.path.islink(path):
                    os.chown(path, user.pw_uid, user.pw_gid)
                    os.chmod(path, 0o666)

        # Pre-create and exclusively lock the output. A conforming resolver must
        # block before its first append and may not rename any fragment yet.
        lock_file = open(RECOVERY_TXT, "w+b", buffering=0)
        os.chown(RECOVERY_TXT, user.pw_uid, user.pw_gid)
        os.chmod(RECOVERY_TXT, 0o666)
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

        def demote():
            os.setgroups([])
            os.setgid(user.pw_gid)
            os.setuid(user.pw_uid)

        process = subprocess.Popen(
            ["/tmp/resolver_verified"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            preexec_fn=demote,
        )

        time.sleep(1.0)
        assert process.poll() is None, "resolver completed while another process held the required output lock"
        assert os.path.getsize(RECOVERY_TXT) == 0, "resolver wrote without obtaining the exclusive OS lock"
        for rel_done in expected_done:
            assert not os.path.exists(os.path.join(LOGS_DIR, rel_done)), "a fragment was renamed before its locked append completed"

        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()
        lock_file = None

        stdout, stderr = process.communicate(timeout=20)
        assert process.returncode == 0, f"compiled resolver failed: stdout={stdout!r} stderr={stderr!r}"

        with open(RECOVERY_TXT, "r", encoding="utf-8") as f:
            actual_lines = [line.rstrip("\n") for line in f]
        assert collections.Counter(actual_lines) == collections.Counter(expected_lines), "fresh fragment contents were not merged exactly once"

        actual_done = set()
        regular_parts = []
        for root, dirs, files in os.walk(LOGS_DIR, followlinks=False):
            for name in files:
                path = os.path.join(root, name)
                rel = os.path.relpath(path, LOGS_DIR)
                if name.endswith(".done") and not os.path.islink(path):
                    actual_done.add(rel)
                if name.endswith(".part") and not os.path.islink(path):
                    regular_parts.append(rel)
        assert actual_done == expected_done
        assert regular_parts == []
        assert os.path.islink(os.path.join(LOGS_DIR, "loop_link"))
        assert os.path.islink(trap_link)
        assert os.path.exists(trap_target)
        with open(trap_target, "r", encoding="utf-8") as f:
            assert f.read() == "SYMLINK_TRAP_MUST_NOT_APPEAR\n"
        assert "SYMLINK_TRAP_MUST_NOT_APPEAR" not in "\n".join(actual_lines)
        assert os.path.isfile(os.path.join(LOGS_DIR, "other", "leave_me.txt"))
    finally:
        if lock_file is not None:
            try:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                lock_file.close()
            except Exception:
                pass
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        if os.path.lexists(LOGS_DIR):
            shutil.rmtree(LOGS_DIR)
        if os.path.exists(backup_logs):
            os.rename(backup_logs, LOGS_DIR)
        shutil.rmtree(backup, ignore_errors=True)
        shutil.rmtree(outside, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
