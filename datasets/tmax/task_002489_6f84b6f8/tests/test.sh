#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import secrets
import signal
import subprocess
import time
import urllib.error
import urllib.request

import pytest

LIB = "/app/libmobilemanifest"
VALIDATOR = "/home/user/validator"
START = "/home/user/start.sh"
URL = "http://localhost:8080/validate"


def run(cmd, cwd=None, timeout=120, env=None):
    result = subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, f"Command failed: {' '.join(cmd)}\n{result.stdout}"
    return result.stdout


def test_01_repaired_library_and_validator_build():
    for name in ("parser.c", "parser.h", "manifest.go", "Makefile", "go.mod"):
        assert os.path.isfile(os.path.join(LIB, name)), f"Missing library file: {name}"

    makefile = open(os.path.join(LIB, "Makefile"), encoding="utf-8").read()
    active_lines = [line for line in makefile.splitlines() if not line.lstrip().startswith("#")]
    assert any("CGO_CFLAGS" in line and "-I" in line for line in active_lines), \
        "Makefile does not set the required CGO_CFLAGS include path"
    assert not any(re.search(r"CGO_ENABLED\s*=\s*0", line) for line in active_lines), \
        "Makefile still disables Cgo"

    env = os.environ.copy()
    env["CGO_ENABLED"] = "1"
    run(["make", "build"], cwd=LIB, env=env)

    # Compile with diagnostics that detect the original fixed-size array overrun.
    run([
        "gcc", "-O2", "-Wall", "-Wextra", "-Warray-bounds", "-Werror",
        "-I.", "-c", "parser.c", "-o", "/tmp/parser_verifier.o"
    ], cwd=LIB)

    dynamic_test = os.path.join(LIB, "zz_verifier_test.go")
    test_source = r'''package libmobilemanifest

import (
    "bytes"
    "testing"
)

func TestVerifierExtractionBoundaryAndPayload(t *testing.T) {
    payload := []byte(`{"version":"v17.23.5","provides":["random-a"],"requires":["random-a"]}`)
    bundle := append(bytes.Repeat([]byte{'H'}, 32), payload...)
    got, err := ExtractManifest(bundle)
    if err != nil {
        t.Fatalf("ExtractManifest rejected a valid bundle: %v", err)
    }
    if got != string(payload) {
        t.Fatalf("wrong extracted payload: got %q want %q", got, payload)
    }
    for _, n := range []int{0, 1, 31, 32} {
        if _, err := ExtractManifest(bytes.Repeat([]byte{'X'}, n)); err == nil {
            t.Fatalf("accepted malformed bundle of length %d", n)
        }
    }
}
'''
    try:
        with open(dynamic_test, "w", encoding="utf-8") as fp:
            fp.write(test_source)
        run(["make", "test"], cwd=LIB, env=env)
    finally:
        try:
            os.remove(dynamic_test)
        except FileNotFoundError:
            pass

    assert os.path.isdir(VALIDATOR), "Missing /home/user/validator project"
    assert os.path.isfile(os.path.join(VALIDATOR, "go.mod")), "Validator is not a Go module"
    go_files = glob.glob(os.path.join(VALIDATOR, "**", "*.go"), recursive=True)
    non_test_go = [p for p in go_files if not p.endswith("_test.go")]
    assert non_test_go, "Validator has no Go implementation"

    source = "\n".join(open(p, encoding="utf-8").read() for p in non_test_go)
    assert "ExtractManifest" in source, "Validator does not call ExtractManifest"

    deps = run(["go", "list", "-deps", "./..."], cwd=VALIDATOR, env=env).splitlines()
    assert "libmobilemanifest" in deps, "Validator does not depend on libmobilemanifest"
    run(["go", "test", "./..."], cwd=VALIDATOR, env=env)
    run(["go", "build", "-o", "/tmp/validator_verifier_bin", "."], cwd=VALIDATOR, env=env)
    symbols = run(["go", "tool", "nm", "/tmp/validator_verifier_bin"], env=env)
    assert "parse_mab" in symbols, "Built validator does not contain the Cgo manifest parser"

    assert os.path.isfile(START), "/home/user/start.sh does not exist"
    assert os.path.getsize(START) > 0, "/home/user/start.sh is empty"


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, encoding="ascii") as fp:
                next(fp, None)
                for line in fp:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for proc in glob.glob("/proc/[0-9]*"):
        try:
            for fd in os.listdir(os.path.join(proc, "fd")):
                try:
                    target = os.readlink(os.path.join(proc, "fd", fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(os.path.basename(proc)))
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def stop_existing_server():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids(8080)
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(1)
    assert not listener_pids(8080), "Could not stop pre-existing server on port 8080"


def wait_for_server():
    for _ in range(30):
        try:
            req = urllib.request.Request("http://localhost:8080/", method="GET")
            urllib.request.urlopen(req, timeout=1)
            return True
        except urllib.error.HTTPError:
            return True
        except Exception:
            time.sleep(0.5)
    return False


def post(data):
    req = urllib.request.Request(URL, data=data, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code


def bundle(manifest, header=None):
    if header is None:
        header = secrets.token_hex(16).encode("ascii")
    assert len(header) == 32
    if isinstance(manifest, bytes):
        payload = manifest
    else:
        payload = json.dumps(manifest, separators=(",", ":")).encode("utf-8")
    return header + payload


def test_02_server_and_behavior():
    # Force verification through the required restart script rather than trusting
    # an unrelated process that happened to occupy the port before verification.
    stop_existing_server()
    subprocess.Popen(
        ["bash", START],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    assert wait_for_server(), "Server did not start on port 8080 using /home/user/start.sh"

    # Preserve the original corpus assertions.
    clean_files = glob.glob("/app/corpora/clean/*.mab")
    evil_files = glob.glob("/app/corpora/evil/*.mab")
    assert clean_files, "No clean corpus files found"
    assert evil_files, "No evil corpus files found"

    failed_clean = []
    for path in clean_files:
        status = post(open(path, "rb").read())
        if status != 200:
            failed_clean.append((os.path.basename(path), status))

    failed_evil = []
    for path in evil_files:
        status = post(open(path, "rb").read())
        if status < 400 or status >= 500:
            failed_evil.append((os.path.basename(path), status))

    assert not failed_clean, f"Clean bundles rejected: {failed_clean}"
    assert not failed_evil, f"Evil bundles accepted: {failed_evil}"

    # Unpredictable manifests prevent classification by hardcoded corpus bodies.
    a = "feature-" + secrets.token_hex(8)
    b = "feature-" + secrets.token_hex(8)
    c = "feature-" + secrets.token_hex(8)
    major = int.from_bytes(os.urandom(2), "big") + 1
    minor = int.from_bytes(os.urandom(1), "big")
    patch = int.from_bytes(os.urandom(1), "big")
    version = f"v{major}.{minor}.{patch}"

    valid = [
        {"version": version, "provides": [a, b, c], "requires": [c, a]},
        {"version": f"v{major + 1}.0.0", "provides": [b], "requires": []},
    ]
    for manifest in valid:
        assert post(bundle(manifest)) == 200, f"Rejected generated valid manifest: {manifest}"

    invalid = [
        {"version": version, "provides": [a], "requires": [b]},
        {"version": f"{major}.{minor}.{patch}", "provides": [a], "requires": [a]},
        {"version": f"v{major}.{minor}", "provides": [a], "requires": [a]},
        {"version": f"v{major}.{minor}.{patch}.1", "provides": [a], "requires": [a]},
        {"provides": [a], "requires": [a]},
    ]
    for manifest in invalid:
        assert post(bundle(manifest)) == 400, f"Did not return 400 for invalid manifest: {manifest}"

    malformed_payloads = [
        b'{"version":"v1.2.3","provides":[',
        b"not-json-" + secrets.token_bytes(8),
    ]
    for payload in malformed_payloads:
        assert post(bundle(payload)) == 400, "Malformed JSON did not return 400"

    for malformed_bundle in (b"", b"x", secrets.token_bytes(31), secrets.token_bytes(32)):
        assert post(malformed_bundle) == 400, "Malformed/short bundle did not return 400"


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-x", "--tb=short"]))
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
