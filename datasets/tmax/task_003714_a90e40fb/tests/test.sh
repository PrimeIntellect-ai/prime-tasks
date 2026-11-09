#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import collections
import fcntl
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import time


def test_go_program_exists_and_uses_flock():
    go_file = "/home/user/processor.go"
    assert os.path.isfile(go_file), f"{go_file} does not exist."
    with open(go_file, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "Flock" in content, "The Go program must use file locking (e.g., syscall.Flock)."

    # Parse the Go source rather than accepting occurrences in comments or strings.
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
    if len(os.Args) != 2 { os.Exit(2) }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(1) }
    hasGo := false
    hasFlock := false
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            hasGo = true
        case *ast.CallExpr:
            if s, ok := x.Fun.(*ast.SelectorExpr); ok && s.Sel.Name == "Flock" {
                hasFlock = true
            }
        }
        return true
    })
    if !hasGo { fmt.Fprintln(os.Stderr, "no goroutine launch found"); os.Exit(1) }
    if !hasFlock { fmt.Fprintln(os.Stderr, "no Flock call found"); os.Exit(1) }
}
'''
    checker_path = "/tmp/check_processor_ast.go"
    with open(checker_path, "w") as f:
        f.write(checker)
    subprocess.run(["go", "run", checker_path, go_file], check=True, timeout=30)


def test_redaction_index_log():
    index_file = "/home/user/redaction_index.log"
    assert os.path.isfile(index_file), f"{index_file} does not exist."

    with open(index_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = {
        "1.txt,2",
        "2.txt,0",
        "3.txt,1",
        "4.txt,3"
    }

    actual_lines = set(lines)
    assert actual_lines == expected_lines, f"Expected index lines {expected_lines}, but got {actual_lines}"
    assert len(lines) == 4, "The index file should contain exactly 4 lines."


def test_processed_logs_archive():
    archive_path = "/home/user/processed_logs.tar.gz"
    assert os.path.isfile(archive_path), f"{archive_path} does not exist."

    expected_suffixes = {
        "Apollo/1.txt",
        "Apollo/3.txt",
        "Gemini/2.txt",
        "Artemis/4.txt"
    }

    expected_contents = {
        "Apollo/1.txt": "Project: Apollo\nSystem booted.\nConnecting to [REDACTED] for updates.\nSecondary connection to [REDACTED] established.\n",
        "Gemini/2.txt": "Project: Gemini\nNo network connection required.\n",
        "Apollo/3.txt": "Project: Apollo\nError connecting to [REDACTED]. Retrying.\n",
        "Artemis/4.txt": "Project: Artemis\nLaunch sequence initiated.\nClient IP: [REDACTED]\nBackup IP: [REDACTED]\nLocalhost: [REDACTED]\n",
    }

    found_suffixes = set()
    matched_contents = {}

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        for member in members:
            if member.isfile():
                for suffix in expected_suffixes:
                    if member.name.endswith(suffix):
                        assert suffix not in found_suffixes, f"Archive contains duplicate output for {suffix}"
                        found_suffixes.add(suffix)
                        f = tar.extractfile(member)
                        content = f.read().decode("utf-8")
                        matched_contents[suffix] = content

                        # Preserve the original content assertions.
                        if suffix == "Apollo/1.txt":
                            assert "[REDACTED]" in content, "1.txt does not contain [REDACTED]"
                            assert "192.168.1.15" not in content, "1.txt still contains 192.168.1.15"
                            assert "10.0.0.2" not in content, "1.txt still contains 10.0.0.2"

                        if suffix == "Artemis/4.txt":
                            assert "8.8.8.8" not in content, "4.txt still contains 8.8.8.8"
                            assert "127.0.0.1" not in content, "4.txt still contains 127.0.0.1"
                            assert content.count("[REDACTED]") == 3, "4.txt should have 3 redactions"

    assert found_suffixes == expected_suffixes, f"Archive is missing some required files. Found: {found_suffixes}"
    assert matched_contents == expected_contents, "Archive contents are not the exact sanitized log contents"


def test_organized_logs_directory_structure():
    base_dir = "/home/user/organized_logs"
    assert os.path.isdir(base_dir), f"{base_dir} does not exist."

    expected_files = {
        "Apollo/1.txt",
        "Apollo/3.txt",
        "Gemini/2.txt",
        "Artemis/4.txt"
    }
    expected_contents = {
        "Apollo/1.txt": "Project: Apollo\nSystem booted.\nConnecting to [REDACTED] for updates.\nSecondary connection to [REDACTED] established.\n",
        "Gemini/2.txt": "Project: Gemini\nNo network connection required.\n",
        "Apollo/3.txt": "Project: Apollo\nError connecting to [REDACTED]. Retrying.\n",
        "Artemis/4.txt": "Project: Artemis\nLaunch sequence initiated.\nClient IP: [REDACTED]\nBackup IP: [REDACTED]\nLocalhost: [REDACTED]\n",
    }

    actual_files = set()
    for root, _, files in os.walk(base_dir):
        for name in files:
            actual_files.add(os.path.relpath(os.path.join(root, name), base_dir))

    for rel_path in expected_files:
        full_path = os.path.join(base_dir, rel_path)
        assert os.path.isfile(full_path), f"Expected file {full_path} is missing from organized_logs."
        with open(full_path, "r") as f:
            assert f.read() == expected_contents[rel_path], f"Incorrect sanitized content in {full_path}"
    assert actual_files == expected_files, f"Unexpected files in organized_logs: {actual_files - expected_files}"


def test_extracted_raw_logs_match_input_archive():
    expected = {}
    with tarfile.open("/home/user/incoming_logs.tar.gz", "r:gz") as tar:
        for member in tar.getmembers():
            if member.isfile() and member.name.endswith(".txt"):
                expected[member.name] = tar.extractfile(member).read()

    actual = {}
    base = "/home/user/raw_logs"
    assert os.path.isdir(base), f"{base} does not exist."
    for root, _, files in os.walk(base):
        for name in files:
            if name.endswith(".txt"):
                path = os.path.join(root, name)
                rel = os.path.relpath(path, base)
                with open(path, "rb") as f:
                    actual[rel] = f.read()

    # Accept extraction with or without retaining the archive's top-level logs directory.
    normalized_expected = {
        (name[len("logs/"):] if name.startswith("logs/") else name): data
        for name, data in expected.items()
    }
    normalized_actual = {
        (name[len("logs/"):] if name.startswith("logs/") else name): data
        for name, data in actual.items()
    }
    assert normalized_actual == normalized_expected, "raw_logs is not an extraction of incoming_logs.tar.gz"


def test_processor_builds_runs_on_derived_inputs_and_obeys_flock():
    binary = "/tmp/submitted_processor"
    subprocess.run(
        ["go", "build", "-o", binary, "/home/user/processor.go"],
        check=True,
        cwd="/home/user",
        timeout=60,
    )

    paths = [
        "/home/user/raw_logs",
        "/home/user/organized_logs",
        "/home/user/redaction_index.log",
    ]
    backup_root = tempfile.mkdtemp(prefix="processor-state-")
    saved = {}
    proc = None
    lock_file = None

    try:
        for i, path in enumerate(paths):
            if os.path.lexists(path):
                backup = os.path.join(backup_root, str(i))
                os.rename(path, backup)
                saved[path] = backup

        raw = "/home/user/raw_logs"
        organized = "/home/user/organized_logs"
        index_path = "/home/user/redaction_index.log"
        os.makedirs(raw)

        expected_files = {}
        expected_index = []
        projects = ["Orion", "Vega", "Lyra"]
        for i in range(36):
            project = projects[i % len(projects)]
            filename = f"case_{i:02d}.txt"
            nested = os.path.join(raw, f"level{i % 4}", f"sub{i % 7}")
            os.makedirs(nested, exist_ok=True)
            if i % 6 == 0:
                body = f"Project: {project}\nNo address appears in record {i}.\n"
                sanitized = body
                count = 0
            elif i % 2 == 0:
                ip = f"10.{i}.1.{(i * 3) % 250 + 1}"
                body = f"Project: {project}\nPeer {ip} contacted {ip}.\n"
                sanitized = body.replace(ip, "[REDACTED]")
                count = 2
            else:
                ip1 = f"172.16.{i}.1"
                ip2 = f"192.168.{i}.2"
                body = f"Project: {project}\nFrom {ip1} to {ip2}.\n"
                sanitized = body.replace(ip1, "[REDACTED]").replace(ip2, "[REDACTED]")
                count = 2
            with open(os.path.join(nested, filename), "w") as f:
                f.write(body)
            expected_files[os.path.join(project, filename)] = sanitized
            expected_index.append(f"{filename},{count}")

        # Hold an exclusive kernel lock on the real index path. A conforming
        # processor must block at its index writes until this lock is released.
        lock_file = open(index_path, "a+")
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        proc = subprocess.Popen([binary], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        time.sleep(1.0)
        lock_file.seek(0)
        assert lock_file.read() == "", "Processor wrote the index while another process held LOCK_EX"
        assert proc.poll() is None, "Processor completed without waiting for the held OS-level file lock"

        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()
        lock_file = None
        stdout, stderr = proc.communicate(timeout=30)
        assert proc.returncode == 0, f"Processor failed on generated inputs: {stdout}\n{stderr}"
        proc = None

        actual_files = {}
        for root, _, files in os.walk(organized):
            for name in files:
                path = os.path.join(root, name)
                rel = os.path.relpath(path, organized)
                with open(path, "r") as f:
                    actual_files[rel] = f.read()
        assert actual_files == expected_files, "Processor did not correctly traverse, organize, and sanitize generated logs"

        with open(index_path, "r") as f:
            lines = [line.rstrip("\n") for line in f]
        assert len(lines) == len(expected_index), "Generated run produced a missing, duplicate, or corrupted index entry"
        assert collections.Counter(lines) == collections.Counter(expected_index), "Generated index counts are incorrect"
        assert all(re.fullmatch(r"case_\d{2}\.txt,\d+", line) for line in lines), "Malformed index line found"
    finally:
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()
        if lock_file is not None:
            try:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                lock_file.close()
            except Exception:
                pass
        for path in paths:
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            elif os.path.lexists(path):
                os.remove(path)
        for path, backup in saved.items():
            os.rename(backup, path)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
