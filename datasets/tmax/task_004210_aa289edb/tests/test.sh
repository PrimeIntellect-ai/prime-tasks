#!/bin/bash
set -u
mkdir -p /logs/verifier

run_verifier() {
    set -e
    cd /home/user/logprocessor

    # First ensure the submitted tests compile and pass without verifier-added tests.
    go test ./...

    # Build and actually execute the requested program. Remove any fabricated
    # artifacts first so only this execution can create them.
    go build -o /tmp/logprocessor-verifier-bin .
    rm -f result.txt mem.pprof
    /tmp/logprocessor-verifier-bin

    cat << 'GO_TEST_EOF' > /home/user/logprocessor/verifier_external_test.go
package main

import (
    "errors"
    "os"
    "path/filepath"
    "reflect"
    "testing"
)

type verifierUploader struct {
    calls [][2]string
    failAt int
}

func (u *verifierUploader) Upload(status, message string) error {
    u.calls = append(u.calls, [2]string{status, message})
    if u.failAt > 0 && len(u.calls) == u.failAt {
        return errors.New("injected upload failure")
    }
    return nil
}

func writeVerifierFixture(t *testing.T, content string) string {
    t.Helper()
    path := filepath.Join(t.TempDir(), "input.jsonl")
    if err := os.WriteFile(path, []byte(content), 0600); err != nil {
        t.Fatal(err)
    }
    return path
}

func TestVerifierProcessLogsBehavior(t *testing.T) {
    path := writeVerifierFixture(t,
        `{"status":"INFO","message":"ignore"}`+"\n"+
        `{"status":"ERROR","message":"first"}`+"\n"+
        `{"status":"error","message":"wrong case"}`+"\n"+
        `{"id":"4","status":"ERROR","message":"second","payload":"payload"}`+"\n")

    uploader := &verifierUploader{}
    count, err := ProcessLogs(path, uploader)
    if err != nil {
        t.Fatalf("ProcessLogs returned unexpected error: %v", err)
    }
    if count != 2 {
        t.Fatalf("count = %d, want 2", count)
    }
    want := [][2]string{{"ERROR", "first"}, {"ERROR", "second"}}
    if !reflect.DeepEqual(uploader.calls, want) {
        t.Fatalf("upload calls = %#v, want %#v", uploader.calls, want)
    }
}

func TestVerifierProcessLogsUploaderFailure(t *testing.T) {
    path := writeVerifierFixture(t,
        `{"status":"ERROR","message":"uploaded"}`+"\n"+
        `{"status":"ERROR","message":"fails"}`+"\n"+
        `{"status":"ERROR","message":"not reached"}`+"\n")

    uploader := &verifierUploader{failAt: 2}
    count, err := ProcessLogs(path, uploader)
    if err == nil {
        t.Fatal("expected uploader error")
    }
    if count != 1 {
        t.Fatalf("count before failure = %d, want 1", count)
    }
    if len(uploader.calls) != 2 {
        t.Fatalf("got %d upload attempts, want 2", len(uploader.calls))
    }
}

func TestVerifierProcessLogsInputErrors(t *testing.T) {
    uploader := &verifierUploader{}
    if _, err := ProcessLogs(filepath.Join(t.TempDir(), "missing.jsonl"), uploader); err == nil {
        t.Fatal("expected an error for a missing input file")
    }

    path := writeVerifierFixture(t, "not-json\n")
    if _, err := ProcessLogs(path, uploader); err == nil {
        t.Fatal("expected malformed NDJSON to return an error")
    }
}
GO_TEST_EOF
    trap 'rm -f /home/user/logprocessor/verifier_external_test.go /tmp/logprocessor-verifier-bin' RETURN

    cat << 'PYTEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import re
import shutil
import subprocess

LOGPROCESSOR_DIR = "/home/user/logprocessor"
BINARY = "/tmp/logprocessor-verifier-bin"


def run(cmd, **kwargs):
    result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_go_mod_exists_and_correct():
    go_mod_path = os.path.join(LOGPROCESSOR_DIR, "go.mod")
    assert os.path.isfile(go_mod_path), f"Expected {go_mod_path} to exist."
    with open(go_mod_path) as f:
        content = f.read()
    assert "module example.com/logprocessor" in content, \
        "go.mod does not contain 'module example.com/logprocessor'."


def test_result_txt_correct():
    result_path = os.path.join(LOGPROCESSOR_DIR, "result.txt")
    assert os.path.isfile(result_path), f"Expected {result_path} to exist."
    with open(result_path) as f:
        content = f.read().strip()
    assert content == "250", \
        f"Expected result.txt to contain '250', but got '{content}'."


def test_mem_pprof_exists_and_valid():
    pprof_path = os.path.join(LOGPROCESSOR_DIR, "mem.pprof")
    assert os.path.isfile(pprof_path), f"Expected {pprof_path} to exist."
    with open(pprof_path, "rb") as f:
        magic_number = f.read(2)
    assert magic_number == b"\x1f\x8b", \
        f"{pprof_path} does not appear to be a valid gzip compressed file."
    with gzip.open(pprof_path, "rb") as f:
        assert f.read(1), "mem.pprof is an empty gzip stream"
    run(["go", "tool", "pprof", "-top", BINARY, pprof_path])


def _process_logs_source(content):
    match = re.search(r"func\s+ProcessLogs\s*\([^)]*\)\s*\([^)]*\)\s*{", content)
    assert match, "ProcessLogs function was not found"
    start = match.start()
    brace = content.find("{", match.start())
    depth = 0
    for i in range(brace, len(content)):
        if content[i] == "{":
            depth += 1
        elif content[i] == "}":
            depth -= 1
            if depth == 0:
                return content[start:i + 1]
    raise AssertionError("Could not parse ProcessLogs body")


def test_main_go_streaming_refactor():
    main_go_path = os.path.join(LOGPROCESSOR_DIR, "main.go")
    assert os.path.isfile(main_go_path), f"Expected {main_go_path} to exist."
    with open(main_go_path) as f:
        content = f.read()

    # Preserve the original assertions.
    assert "os.ReadFile" not in content, "main.go still contains 'os.ReadFile'."
    assert "ioutil.ReadFile" not in content, "main.go still contains 'ioutil.ReadFile'."
    assert "os.Open" in content, "main.go does not contain 'os.Open'."

    body = _process_logs_source(content)
    assert "os.Open" in body, "ProcessLogs itself must open the input file."
    assert any(token in body for token in (
        "bufio.NewScanner", "json.NewDecoder", "bufio.NewReader"
    )), "ProcessLogs does not use a standard streaming reader."
    for forbidden in ("ReadFile", "ReadAll", "strings.Split", "bytes.Split"):
        assert forbidden not in body, \
            f"ProcessLogs uses non-streaming operation {forbidden}."


def test_main_test_go_exists_and_passes():
    test_go_path = os.path.join(LOGPROCESSOR_DIR, "main_test.go")
    assert os.path.isfile(test_go_path), f"Expected {test_go_path} to exist."
    with open(test_go_path) as f:
        source = f.read()
    assert re.search(r"func\s+Test\w+\s*\(\s*t\s+\*testing\.T\s*\)", source), \
        "main_test.go does not define a Go unit test."
    assert "ProcessLogs(" in source, "main_test.go does not test ProcessLogs."
    assert re.search(r"func\s*\([^)]*\)\s*Upload\s*\(", source), \
        "main_test.go does not implement a mock Uploader."
    run(["go", "test"], cwd=LOGPROCESSOR_DIR)


def test_main_uses_current_input_and_regenerates_artifacts():
    data_path = os.path.join(LOGPROCESSOR_DIR, "data.jsonl")
    result_path = os.path.join(LOGPROCESSOR_DIR, "result.txt")
    profile_path = os.path.join(LOGPROCESSOR_DIR, "mem.pprof")
    backup = data_path + ".verifier-backup"
    shutil.copyfile(data_path, backup)
    try:
        fixture = "".join([
            '{"status":"ERROR","message":"a"}\n',
            '{"status":"INFO","message":"b"}\n',
            '{"status":"ERROR","message":"c"}\n',
            '{"status":"WARN","message":"d"}\n',
            '{"status":"ERROR","message":"e"}\n',
        ])
        with open(data_path, "w") as f:
            f.write(fixture)
        for path in (result_path, profile_path):
            if os.path.exists(path):
                os.remove(path)
        run([BINARY], cwd=LOGPROCESSOR_DIR)
        with open(result_path) as f:
            assert f.read().strip() == "3", \
                "main did not derive result.txt from the current data.jsonl"
        assert os.path.isfile(profile_path), "main did not regenerate mem.pprof"
        run(["go", "tool", "pprof", "-top", BINARY, profile_path])
    finally:
        shutil.move(backup, data_path)
        for path in (result_path, profile_path):
            if os.path.exists(path):
                os.remove(path)
        # Restore the required final artifacts using the original fixture.
        run([BINARY], cwd=LOGPROCESSOR_DIR)

    with open(result_path) as f:
        assert f.read().strip() == "250"
PYTEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short
}

if run_verifier 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -f /home/user/logprocessor/verifier_external_test.go /tmp/logprocessor-verifier-bin
