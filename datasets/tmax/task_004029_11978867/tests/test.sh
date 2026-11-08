#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile

GO_FILE = "/home/user/wal_filter.go"


def run_filter(input_dir, output_dir, log_path, timeout=45):
    try:
        return subprocess.run(
            ["go", "run", GO_FILE, "-in", input_dir, "-out", output_dir, "-log", log_path],
            check=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.CalledProcessError as e:
        assert False, (
            "Go program failed to execute or compile:\n"
            f"STDOUT:\n{e.stdout}\nSTDERR:\n{e.stderr}"
        )
    except subprocess.TimeoutExpired:
        assert False, f"Go program timed out after {timeout} seconds."


def encode_rle(text):
    raw = text.encode("ascii")
    encoded = bytearray()
    i = 0
    while i < len(raw):
        j = i + 1
        while j < len(raw) and raw[j] == raw[i]:
            j += 1
        remaining = j - i
        while remaining:
            count = min(255, remaining)
            encoded.extend((count, raw[i]))
            remaining -= count
        i = j
    return bytes(encoded)


def test_source_uses_concurrency_and_log_synchronization():
    assert os.path.isfile(GO_FILE), f"The required Go program {GO_FILE} does not exist."

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
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    hasGo := false
    hasMutexOrFileLock := false
    hasChan := false
    hasSend := false

    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            hasGo = true
        case *ast.ChanType:
            hasChan = true
        case *ast.SendStmt:
            hasSend = true
        case *ast.SelectorExpr:
            switch x.Sel.Name {
            case "Mutex", "RWMutex", "Flock", "O_APPEND":
                hasMutexOrFileLock = true
            }
        }
        return true
    })

    if !hasGo {
        fmt.Fprintln(os.Stderr, "the program does not contain a goroutine launch")
        os.Exit(1)
    }
    if !hasMutexOrFileLock && !(hasChan && hasSend) {
        fmt.Fprintln(os.Stderr, "the program does not use a mutex, file-lock/atomic-append mechanism, or channel-based log serialization")
        os.Exit(1)
    }
}
'''
    checker_src = "/tmp/check_wal_source.go"
    checker_bin = "/tmp/check_wal_source"
    with open(checker_src, "w") as f:
        f.write(checker)
    built = subprocess.run(
        ["go", "build", "-o", checker_bin, checker_src],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert built.returncode == 0, f"Could not build source checker: {built.stderr}"
    checked = subprocess.run(
        [checker_bin, GO_FILE], capture_output=True, text=True, timeout=10
    )
    assert checked.returncode == 0, checked.stderr.strip()


def test_original_corpora():
    assert os.path.isfile(GO_FILE), f"The required Go program {GO_FILE} does not exist."

    clean_corpus = "/app/corpus/clean"
    evil_corpus = "/app/corpus/evil"

    assert os.path.isdir(clean_corpus), f"Clean corpus directory {clean_corpus} is missing."
    assert os.path.isdir(evil_corpus), f"Evil corpus directory {evil_corpus} is missing."

    clean_files = set(os.listdir(clean_corpus))
    evil_files = set(os.listdir(evil_corpus))

    with tempfile.TemporaryDirectory() as temp_in, tempfile.TemporaryDirectory() as temp_out, tempfile.NamedTemporaryFile(mode="w+", delete=False) as temp_log:
        log_path = temp_log.name

        for name in clean_files:
            shutil.copy(os.path.join(clean_corpus, name), os.path.join(temp_in, name))
        for name in evil_files:
            shutil.copy(os.path.join(evil_corpus, name), os.path.join(temp_in, name))

        run_filter(temp_in, temp_out, log_path, timeout=30)

        with open(log_path, "r") as f:
            log_lines = f.read().splitlines()

        log_entries = {}
        for line in log_lines:
            if ":" in line:
                fname, status = line.split(":", 1)
                log_entries[fname.strip()] = status.strip()

        out_files = set(os.listdir(temp_out))
        evil_bypassed = []
        clean_modified_or_missing = []

        for name in evil_files:
            if name in out_files:
                evil_bypassed.append(f"{name} (copied to out dir)")
            elif log_entries.get(name) != "EVIL":
                evil_bypassed.append(f"{name} (not logged as EVIL)")

        for name in clean_files:
            if name not in out_files:
                clean_modified_or_missing.append(f"{name} (missing from out dir)")
            else:
                orig = os.path.join(clean_corpus, name)
                copied = os.path.join(temp_out, name)
                with open(orig, "rb") as f1, open(copied, "rb") as f2:
                    if f1.read() != f2.read():
                        clean_modified_or_missing.append(f"{name} (content modified)")

            if log_entries.get(name) != "CLEAN":
                clean_modified_or_missing.append(f"{name} (not logged as CLEAN)")

        error_msgs = []
        if evil_bypassed:
            error_msgs.append(
                f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
                + ", ".join(evil_bypassed)
            )
        if clean_modified_or_missing:
            error_msgs.append(
                f"{len(clean_modified_or_missing)} of {len(clean_files)} clean modified/rejected: "
                + ", ".join(clean_modified_or_missing)
            )
        assert not error_msgs, " | ".join(error_msgs)


def test_generated_rle_wals_and_stress_logging():
    rng = secrets.SystemRandom()
    expected = {}
    original_bytes = {}

    with tempfile.TemporaryDirectory() as root:
        temp_in = os.path.join(root, "input")
        temp_out = os.path.join(root, "output")
        log_path = os.path.join(root, "summary.log")
        os.mkdir(temp_in)
        os.mkdir(temp_out)

        prefix = secrets.token_hex(8)
        count = 160
        for i in range(count):
            evil = (i % 4 == 1) or (i % 11 == 0)
            name = f"{prefix}_{i:03d}_{secrets.token_hex(3)}.wal.rle"

            txn1 = 1000 + i
            if txn1 == 666:
                txn1 += 10000
            repeated = "A" * (300 if i % 17 == 0 else 8 + (i % 19))

            lines = [
                f"TXN:{txn1} DATA:sensor={repeated};literal=666;note=TXN:666",
                f"TXN:{20000 + i} DATA:reading_{rng.randrange(100000, 999999)}=ok",
            ]
            if evil:
                insert_at = rng.randrange(0, len(lines) + 1)
                lines.insert(insert_at, f"TXN:666 DATA:malicious_{secrets.token_hex(5)}")
                expected[name] = "EVIL"
            else:
                lines.append(f"TXN:{6660 + i} DATA:near_but_clean=BBBBBBBBBBBB")
                expected[name] = "CLEAN"

            encoded = encode_rle("\n".join(lines) + "\n")
            assert any(encoded[j] > 1 for j in range(0, len(encoded), 2)), "fixture must exercise RLE counts"
            original_bytes[name] = encoded
            with open(os.path.join(temp_in, name), "wb") as f:
                f.write(encoded)

        run_filter(temp_in, temp_out, log_path, timeout=60)

        assert os.path.isfile(log_path), "The requested log file was not created."
        with open(log_path, "r", encoding="utf-8") as f:
            log_lines = f.read().splitlines()

        assert len(log_lines) == len(expected), (
            f"Expected exactly {len(expected)} complete log lines, got {len(log_lines)}; "
            "entries may be missing, duplicated, or garbled."
        )

        actual = {}
        line_pattern = re.compile(r"^([^:\n]+): (CLEAN|EVIL)$")
        for line in log_lines:
            match = line_pattern.fullmatch(line)
            assert match, f"Malformed or garbled log line: {line!r}"
            name, status = match.groups()
            assert name not in actual, f"Duplicate log entry for {name}"
            actual[name] = status

        assert actual == expected, "Generated WAL classifications or log filenames are incorrect."

        expected_out = {name for name, status in expected.items() if status == "CLEAN"}
        actual_out = set(os.listdir(temp_out))
        assert actual_out == expected_out, (
            f"Output directory mismatch. Missing: {sorted(expected_out - actual_out)}; "
            f"unexpected: {sorted(actual_out - expected_out)}"
        )

        for name in expected_out:
            with open(os.path.join(temp_out, name), "rb") as f:
                copied = f.read()
            assert copied == original_bytes[name], f"Clean compressed file {name} was modified."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
