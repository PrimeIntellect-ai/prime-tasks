#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_TEST_EOF' > /home/user/gateway/verifier_fallback_test.go
//go:build fallback
// +build fallback

package main

import (
    "context"
    "net/http"
    "runtime"
    "testing"
    "time"
)

func TestVerifierFallbackBehavior(t *testing.T) {
    limiter := NewLimiter()

    validReq, err := http.NewRequest("GET", "/", nil)
    if err != nil {
        t.Fatal(err)
    }
    validReq.Header.Set("X-App-Config", "valid-config")
    if !limiter.Allow(validReq) {
        t.Fatal("fallback limiter rejected a request with valid configuration")
    }

    invalidReq, err := http.NewRequest("GET", "/", nil)
    if err != nil {
        t.Fatal(err)
    }
    if limiter.Allow(invalidReq) {
        t.Fatal("fallback limiter accepted a request without X-App-Config")
    }
}

func TestVerifierFallbackCancellationDoesNotLeak(t *testing.T) {
    limiter := NewLimiter()
    runtime.GC()
    time.Sleep(20 * time.Millisecond)
    before := runtime.NumGoroutine()

    for i := 0; i < 500; i++ {
        ctx, cancel := context.WithCancel(context.Background())
        req, err := http.NewRequestWithContext(ctx, "GET", "/", nil)
        if err != nil {
            t.Fatal(err)
        }
        cancel()
        if limiter.Allow(req) {
            t.Fatal("fallback limiter allowed a cancelled request")
        }
    }

    runtime.GC()
    time.Sleep(200 * time.Millisecond)
    after := runtime.NumGoroutine()
    if after > before+25 {
        t.Fatalf("fallback limiter leaked goroutines: before=%d after=%d", before, after)
    }
}
GO_TEST_EOF

cat << 'PYTEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
import tempfile

GATEWAY_DIR = "/home/user/gateway"
BUILD_DIR = os.path.join(GATEWAY_DIR, "build")


def run(cmd, **kwargs):
    result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {' '.join(cmd)}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def assert_elf_machine(binary_path, expected_machine, architecture):
    assert os.path.isfile(binary_path), f"Missing binary: {binary_path}"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary_path} is not an ELF binary"
        f.seek(18)
        machine = f.read(2)
    assert machine == expected_machine, f"Expected {architecture} architecture, got {machine}"


def assert_reproducible_gateway_build(binary_path, goarch, tag):
    env = os.environ.copy()
    env.update({"GOOS": "linux", "GOARCH": goarch})
    with tempfile.TemporaryDirectory() as tmp:
        expected = os.path.join(tmp, "gateway")
        run(["go", "build", "-tags", tag, "-o", expected, "."], cwd=GATEWAY_DIR, env=env)
        assert sha256(binary_path) == sha256(expected), (
            f"{binary_path} is not the gateway built from the submitted source "
            f"for linux/{goarch} with tag {tag}"
        )

    info = run(["go", "version", "-m", binary_path]).stdout
    assert re.search(r"build\s+-tags=" + re.escape(tag) + r"(?:\s|$)", info), (
        f"{binary_path} does not record the required {tag} build tag:\n{info}"
    )
    assert re.search(r"build\s+GOOS=linux(?:\s|$)", info), info
    assert re.search(r"build\s+GOARCH=" + re.escape(goarch) + r"(?:\s|$)", info), info


def test_validation_fixture_was_updated():
    path = os.path.join(GATEWAY_DIR, "limiter_test.go")
    assert os.path.isfile(path), "limiter_test.go is missing"
    source = open(path, encoding="utf-8").read()
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//.*?$", "", source, flags=re.M)
    match = re.search(r"func\s+TestLimiter_Validation\s*\([^)]*\)\s*\{", source)
    assert match, "TestLimiter_Validation is missing"
    start = match.end() - 1
    depth = 0
    end = None
    for index in range(start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                end = index
                break
    assert end is not None, "Could not parse TestLimiter_Validation"
    body = source[start:end + 1]
    fixture = re.compile(
        r"req\s*\.\s*Header\s*\.\s*(?:Set|Add)\s*\(\s*[\"`]X-App-Config[\"`]\s*,\s*[\"`]valid-config[\"`]\s*\)"
    )
    assert fixture.search(body), (
        "TestLimiter_Validation must set X-App-Config to valid-config on req"
    )


def test_tests_pass_fallback():
    result = subprocess.run(
        ["go", "test", "-count=1", "-tags=fallback", "./..."],
        cwd=GATEWAY_DIR,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Tests failed for fallback tag:\n{result.stdout}\n{result.stderr}"


def test_tests_pass_fast():
    result = subprocess.run(
        ["go", "test", "-count=1", "-tags=fast", "./..."],
        cwd=GATEWAY_DIR,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Tests failed for fast tag:\n{result.stdout}\n{result.stderr}"


def test_fast_amd64_binary():
    binary_path = os.path.join(BUILD_DIR, "gateway_fast_amd64")
    assert_elf_machine(binary_path, b"\x3e\x00", "AMD64")
    assert_reproducible_gateway_build(binary_path, "amd64", "fast")
    result = run([binary_path], cwd=GATEWAY_DIR, timeout=10)
    assert "Gateway started with limiter:" in result.stdout, result.stdout


def test_fallback_arm64_binary():
    binary_path = os.path.join(BUILD_DIR, "gateway_fallback_arm64")
    assert_elf_machine(binary_path, b"\xb7\x00", "ARM64")
    assert_reproducible_gateway_build(binary_path, "arm64", "fallback")
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -f /home/user/gateway/verifier_fallback_test.go
