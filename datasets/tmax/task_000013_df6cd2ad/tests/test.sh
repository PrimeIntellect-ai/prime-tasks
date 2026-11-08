#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import subprocess
import tempfile
import time
import urllib.request
import pytest

ROOT = "/home/user/webapp"
LINUX_BIN = ROOT + "/build/server_linux"
WINDOWS_BIN = ROOT + "/build/server_windows.exe"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kwargs)


def go_env(goos, **extra):
    env = os.environ.copy()
    env.update({"GOOS": goos, "GOARCH": "amd64", "CGO_ENABLED": "0"})
    env.update(extra)
    return env


def test_binaries_exist_and_format():
    assert os.path.isfile(LINUX_BIN), f"Linux binary not found at {LINUX_BIN}"
    assert os.path.isfile(WINDOWS_BIN), f"Windows binary not found at {WINDOWS_BIN}"

    # Preserve the original magic-byte assertions.
    with open(LINUX_BIN, "rb") as f:
        magic = f.read(4)
        assert magic == b"\x7fELF", f"{LINUX_BIN} is not a valid ELF executable"
        f.seek(18)
        assert f.read(2) == b"\x3e\x00", "Linux executable is not amd64 ELF"

    with open(WINDOWS_BIN, "rb") as f:
        magic = f.read(2)
        assert magic == b"MZ", f"{WINDOWS_BIN} is not a valid PE executable"
        f.seek(0x3c)
        pe_offset = struct.unpack("<I", f.read(4))[0]
        f.seek(pe_offset)
        assert f.read(4) == b"PE\0\0", "Windows executable has no valid PE header"
        assert struct.unpack("<H", f.read(2))[0] == 0x8664, "Windows executable is not amd64 PE"

    for path, goos in ((LINUX_BIN, "linux"), (WINDOWS_BIN, "windows")):
        info = run(["go", "version", "-m", path]).stdout
        assert "path\texample.com/webapp" in info, f"{path} is not the webapp Go executable"
        assert f"GOOS={goos}" in info, f"{path} was not built for {goos}"
        assert "GOARCH=amd64" in info, f"{path} was not built for amd64"

    with open(WINDOWS_BIN, "rb") as f:
        assert b"Processed on Windows" in f.read(), "Windows application lacks its processor response"


def test_windows_build_tags():
    proc_windows_path = ROOT + "/proc_windows.go"
    assert os.path.isfile(proc_windows_path), f"File {proc_windows_path} is missing."
    with open(proc_windows_path, "r") as f:
        content = f.read()
    has_new_tag = "go:build windows" in content
    has_old_tag = "+build windows" in content
    assert has_new_tag or has_old_tag, f"Missing Windows build tag in {proc_windows_path}"


def test_memory_leak_fixed_source_assertion():
    thumbnail_path = ROOT + "/thumbnail.go"
    assert os.path.isfile(thumbnail_path), f"File {thumbnail_path} is missing."
    with open(thumbnail_path, "r") as f:
        content = f.read()
    assert "LeakCache = append" not in content, f"Memory leak is not fixed in {thumbnail_path}"


def test_patch_applied():
    main_go_path = ROOT + "/main.go"
    assert os.path.isfile(main_go_path), f"File {main_go_path} is missing."
    with open(main_go_path, "r") as f:
        content = f.read()
    assert "HandleThumbnail" in content, f"Patch was not properly applied to {main_go_path}"
    assert "PATCH_INSERT_ROUTE" not in content, f"Patch was not properly applied to {main_go_path}"


def test_os_file_selection_and_cross_builds():
    linux_list = run(
        ["go", "list", "-f", "{{join .GoFiles \",\"}}|{{join .IgnoredGoFiles \",\"}}", "."],
        cwd=ROOT, env=go_env("linux"), timeout=30
    ).stdout.strip().split("|", 1)
    windows_list = run(
        ["go", "list", "-f", "{{join .GoFiles \",\"}}|{{join .IgnoredGoFiles \",\"}}", "."],
        cwd=ROOT, env=go_env("windows"), timeout=30
    ).stdout.strip().split("|", 1)

    assert "proc_linux.go" in linux_list[0] and "proc_windows.go" in linux_list[1]
    assert "proc_windows.go" in windows_list[0] and "proc_linux.go" in windows_list[1]

    with tempfile.TemporaryDirectory() as td:
        run(["go", "build", "-o", os.path.join(td, "server_linux"), "."],
            cwd=ROOT, env=go_env("linux"), timeout=120)
        run(["go", "build", "-o", os.path.join(td, "server_windows.exe"), "."],
            cwd=ROOT, env=go_env("windows"), timeout=120)


def test_linux_binary_serves_real_endpoint():
    proc = subprocess.Popen(
        [LINUX_BIN], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        start_new_session=True
    )
    try:
        deadline = time.time() + 15
        last_error = None
        while time.time() < deadline:
            assert proc.poll() is None, "Linux server exited before serving requests"
            try:
                with urllib.request.urlopen("http://127.0.0.1:8080/thumbnail", timeout=1) as response:
                    body = response.read().decode()
                    assert response.status == 200
                    assert body == "Processed on Linux"
                with urllib.request.urlopen("http://127.0.0.1:8080/", timeout=1) as response:
                    assert response.status == 200
                    assert response.read().decode() == "Hello"
                return
            except Exception as exc:
                last_error = exc
                time.sleep(0.2)
        pytest.fail(f"Linux server did not serve the required endpoint: {last_error}")
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)


def test_handler_behavior_and_retained_memory():
    fd, test_path = tempfile.mkstemp(prefix="zz_verifier_", suffix="_test.go", dir=ROOT)
    os.close(fd)
    source = r'''package main

import (
    "net/http/httptest"
    "runtime"
    "runtime/debug"
    "testing"
)

func TestVerifierThumbnailDoesNotRetainRequests(t *testing.T) {
    runtime.GC()
    debug.FreeOSMemory()
    var before, after runtime.MemStats
    runtime.ReadMemStats(&before)

    for i := 0; i < 12; i++ {
        req := httptest.NewRequest("GET", "/thumbnail", nil)
        rec := httptest.NewRecorder()
        HandleThumbnail(rec, req)
        if rec.Code != 200 {
            t.Fatalf("request %d returned status %d", i, rec.Code)
        }
        if got := rec.Body.String(); got != "Processed on Linux" {
            t.Fatalf("request %d returned %q", i, got)
        }
    }

    runtime.GC()
    debug.FreeOSMemory()
    runtime.ReadMemStats(&after)
    delta := int64(after.Alloc) - int64(before.Alloc)
    if delta > 32*1024*1024 {
        t.Fatalf("thumbnail requests retained %d bytes", delta)
    }
}
'''
    try:
        with open(test_path, "w") as f:
            f.write(source)
        run(["go", "test", "-run", "^TestVerifierThumbnailDoesNotRetainRequests$", "-count=1", "."],
            cwd=ROOT, env=go_env("linux"), timeout=120)
    finally:
        try:
            os.unlink(test_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
