#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

import pytest

ROOT = "/app/safe-router-1.1.0"
BINARY = os.path.join(ROOT, "safe-router")
SCRIPT = "/home/user/ci-run.sh"
CORPUS = "/app/corpus"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_ci_run_script_really_builds_and_verifies():
    assert os.path.isfile(SCRIPT), f"Expected script {SCRIPT} to exist."
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Expected {SCRIPT} to be executable."

    filter_path = os.path.join(ROOT, "filter.go")
    with open(filter_path, "rb") as f:
        original_filter = f.read()

    # A missing binary plus uncompilable source must make the CI build fail.
    if os.path.exists(BINARY):
        os.remove(BINARY)
    try:
        with open(filter_path, "wb") as f:
            f.write(b"package main\nfunc thisDoesNotCompile( {\n")
        failed_build = run(["bash", SCRIPT], timeout=60)
        assert failed_build.returncode != 0, (
            "ci-run.sh returned success when the project could not be built.\n"
            f"STDOUT:\n{failed_build.stdout}\nSTDERR:\n{failed_build.stderr}"
        )
    finally:
        with open(filter_path, "wb") as f:
            f.write(original_filter)

    # Add a valid but clean request to the evil corpus. A genuine invocation of
    # the corpus verifier must fail and that failure must be propagated.
    probe_name = ".verifier-clean-in-evil-" + secrets.token_hex(8) + ".http"
    probe_path = os.path.join(CORPUS, "evil", probe_name)
    with open(probe_path, "w") as f:
        f.write(
            "GET /ci-probe-" + secrets.token_hex(8) + "/index.html HTTP/1.1\r\n"
            "Host: ci-probe.example\r\n"
            "User-Agent: benign-ci-agent\r\n\r\n"
        )
    try:
        failed_verify = run(["bash", SCRIPT], timeout=60)
        assert os.path.exists(probe_path), "ci-run.sh must not delete or rewrite the supplied corpus."
        assert failed_verify.returncode != 0, (
            "ci-run.sh returned success even though corpus verification had to fail.\n"
            f"STDOUT:\n{failed_verify.stdout}\nSTDERR:\n{failed_verify.stderr}"
        )
    finally:
        if os.path.exists(probe_path):
            os.remove(probe_path)

    # With the real sources and corpus restored, the script must build and pass.
    if os.path.exists(BINARY):
        os.remove(BINARY)
    result = run(["bash", SCRIPT], timeout=60)
    assert result.returncode == 0, (
        f"ci-run.sh failed with exit code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert os.path.isfile(BINARY), "ci-run.sh did not create the safe-router binary."
    assert os.access(BINARY, os.X_OK), "The built safe-router binary is not executable."


def test_symlink_and_directory():
    backend_dir = "/home/user/backend"
    symlink_path = "/home/user/active-upstream.sock"
    assert os.path.isdir(backend_dir), f"Expected directory {backend_dir} to exist."
    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symbolic link."
    assert os.readlink(symlink_path) == "/home/user/backend/app.sock", (
        f"Symlink {symlink_path} does not point to /home/user/backend/app.sock."
    )


def test_makefile_fixed():
    makefile_path = os.path.join(ROOT, "Makefile")
    assert os.path.isfile(makefile_path), "Makefile is missing."
    with open(makefile_path, "r") as f:
        lines = f.readlines()
    assert any(line.startswith("\t") for line in lines), (
        "Makefile does not seem to be fixed (no tab characters found for recipes)."
    )

    # Exercise the repaired Makefile rather than relying only on its text.
    result = run(["make", "clean", "build"], cwd=ROOT, timeout=60)
    assert result.returncode == 0, f"Makefile build failed:\n{result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)


def test_main_go_fixed_and_runtime_uses_environment():
    main_go_path = os.path.join(ROOT, "main.go")
    assert os.path.isfile(main_go_path), "main.go is missing."
    with open(main_go_path, "r") as f:
        content = f.read()
    assert "UPSTREAM_SOCK" in content, "main.go does not mention UPSTREAM_SOCK."
    assert "/var/run/broken.sock" not in content, "main.go still contains the hardcoded broken socket path."

    build = run(["go", "build", "-o", BINARY, "."], cwd=ROOT, timeout=60)
    assert build.returncode == 0, f"Failed to build safe-router:\n{build.stderr}"

    random_socket = "/tmp/upstream-" + secrets.token_hex(16) + ".sock"
    env = os.environ.copy()
    env["UPSTREAM_SOCK"] = random_socket
    result = run([BINARY], cwd=ROOT, env=env, timeout=10)
    assert result.returncode == 0, f"safe-router failed at runtime:\n{result.stderr}"
    combined = result.stdout + result.stderr
    assert random_socket in combined, (
        "The running binary did not use the dynamically supplied UPSTREAM_SOCK value."
    )


def build_filter_runner(tmpdir):
    runner_source = r'''package main

import (
    "encoding/json"
    "fmt"
    "net/http"
    "net/url"
    "os"
)

type Input struct {
    Path string `json:"path"`
    RawPath string `json:"raw_path"`
    Host string `json:"host"`
    XFH string `json:"xfh"`
    HasXFH bool `json:"has_xfh"`
    UA string `json:"ua"`
}

func main() {
    if len(os.Args) != 2 { os.Exit(2) }
    var in Input
    if err := json.Unmarshal([]byte(os.Args[1]), &in); err != nil { os.Exit(3) }
    req := &http.Request{
        Method: "GET",
        URL: &url.URL{Path: in.Path, RawPath: in.RawPath},
        Host: in.Host,
        Header: make(http.Header),
    }
    if in.HasXFH { req.Header.Set("X-Forwarded-Host", in.XFH) }
    if in.UA != "" { req.Header.Set("User-Agent", in.UA) }
    fmt.Println(IsMalicious(req))
}
'''
    runner_go = os.path.join(tmpdir, "runner.go")
    runner_bin = os.path.join(tmpdir, "filter-runner")
    with open(runner_go, "w") as f:
        f.write(runner_source)
    result = run(
        ["go", "build", "-o", runner_bin, os.path.join(ROOT, "filter.go"), runner_go],
        cwd=ROOT,
        timeout=60,
    )
    assert result.returncode == 0, f"Failed to compile filter test runner:\n{result.stderr}"
    return runner_bin


def test_filter_on_derived_randomized_requests():
    token = secrets.token_hex(12)
    host = token + ".example"
    other_host = secrets.token_hex(12) + ".invalid"

    cases = []
    # Clean controls, including matching forwarded hosts and benign encoded paths.
    for i in range(8):
        part = secrets.token_hex(8)
        cases.append(({
            "path": f"/{part}/index-{i}.html",
            "raw_path": "",
            "host": host,
            "xfh": host,
            "has_xfh": i % 2 == 0,
            "ua": f"Mozilla/{part}",
        }, False, "clean control"))
    cases.append(({
        "path": f"/{token}/file name.txt",
        "raw_path": f"/{token}/file%20name.txt",
        "host": host,
        "xfh": "",
        "has_xfh": False,
        "ua": "ordinary-scanner-free-client",
    }, False, "benign URL encoding"))

    # Literal and encoded traversal forms at non-fixed randomized locations.
    traversal = [
        (f"/{token}/../secret", ""),
        (f"/{token}/a/../../secret", ""),
        (f"/{token}/..//secret", f"/{token}/%2e%2e%2f/secret"),
        (f"/{token}/..//secret", f"/{token}/%2E%2E%2F/secret"),
        (f"/{token}/../secret", f"/{token}/%2e%2E/secret"),
    ]
    for path, raw_path in traversal:
        cases.append(({
            "path": path, "raw_path": raw_path, "host": host,
            "xfh": "", "has_xfh": False, "ua": "benign-client",
        }, True, "directory traversal"))

    # Header mismatch independently triggers rejection; equality remains allowed.
    for i in range(5):
        cases.append(({
            "path": f"/{secrets.token_hex(6)}/ok", "raw_path": "", "host": host,
            "xfh": other_host + str(i), "has_xfh": True, "ua": "benign-client",
        }, True, "X-Forwarded-Host mismatch"))

    # User-Agent matching must be case-insensitive and work as a substring.
    for ua in [
        f"prefix-{token}-sqlmap-suffix",
        f"prefix-SQLMAP-{token}",
        f"client-nMaP/{token}",
        f"NMAP-{token}-client",
    ]:
        cases.append(({
            "path": f"/{secrets.token_hex(6)}/ok", "raw_path": "", "host": host,
            "xfh": "", "has_xfh": False, "ua": ua,
        }, True, "malicious User-Agent"))

    with tempfile.TemporaryDirectory() as tmpdir:
        runner = build_filter_runner(tmpdir)
        failures = []
        for data, expected, label in cases:
            result = run([runner, json.dumps(data)], timeout=10)
            actual = result.stdout.strip().lower()
            wanted = "true" if expected else "false"
            if result.returncode != 0 or actual != wanted:
                failures.append(
                    f"{label}: expected {wanted}, got rc={result.returncode}, output={result.stdout!r}, err={result.stderr!r}"
                )
        assert not failures, "\n".join(failures)


def test_original_corpus_and_builtin_verification():
    # Preserve the original per-file corpus assertion.
    with tempfile.TemporaryDirectory() as tmpdir:
        runner = build_filter_runner(tmpdir)
        errors = []
        for category, expected in (("evil", "true"), ("clean", "false")):
            directory = os.path.join(CORPUS, category)
            for name in os.listdir(directory):
                if not name.endswith(".http"):
                    continue
                path = os.path.join(directory, name)
                # Use a small parser program through the actual built-in verifier below;
                # randomized direct tests above exercise IsMalicious independently.
                assert os.path.isfile(path)

        result = run([BINARY, "verify", "--corpus", CORPUS], cwd=ROOT, timeout=30)
        assert result.returncode == 0, (
            "The required built-in corpus verification command failed.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        assert "Corpus verification passed" in result.stdout
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
