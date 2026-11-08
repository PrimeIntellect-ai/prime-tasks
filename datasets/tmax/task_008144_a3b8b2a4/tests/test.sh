#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import os
import re
import sys
import json
import time
import shutil
import socket
import secrets
import struct
import tempfile
import threading
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOME = "/home/user"
PROJECT = "/home/user/rust_calc"
OPS = os.path.join(PROJECT, "ops.dat")
ENCODED = os.path.join(PROJECT, "src", "encoded_ops.rs")
BINARY = os.path.join(PROJECT, "target", "debug", "rust_calc")
ORCHESTRATOR = os.path.join(HOME, "build_orchestrator.py")
TEST_SUITE = os.path.join(HOME, "test_cli.py")
SUCCESS = os.path.join(HOME, "success.log")


def run(cmd, **kwargs):
    kwargs.setdefault("cwd", PROJECT)
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 120)
    result = subprocess.run(cmd, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


class TelemetryHandler(BaseHTTPRequestHandler):
    requests_seen = []

    def do_GET(self):
        type(self).requests_seen.append(self.path)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def log_message(self, fmt, *args):
        pass


def start_server():
    TelemetryHandler.requests_seen = []
    server = ThreadingHTTPServer(("127.0.0.1", 8080), TelemetryHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread


def stop_server(server, thread):
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)


def invoke_binary(op_id, value, expected):
    try:
        result = subprocess.run(
            [BINARY, str(op_id), str(value)],
            capture_output=True,
            text=True,
            timeout=8,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError("Rust binary timed out. Is the mock server missing or hanging?")
    assert result.returncode == 0, f"Rust binary exited non-zero: {result.stderr}"
    assert result.stdout.strip() == str(expected), (
        f"Expected {expected} for op {op_id}, input {value}; got {result.stdout!r}"
    )


def check_required_files_and_original_assertions():
    assert os.path.isfile(SUCCESS), f"Expected {SUCCESS} to exist."
    with open(SUCCESS, "r", encoding="utf-8") as f:
        success_content = f.read().strip()
    assert "ALL_TESTS_PASSED" in success_content, "Expected success.log to contain ALL_TESTS_PASSED."
    assert success_content == "ALL_TESTS_PASSED", "success.log must contain the exact success token."

    assert os.path.isfile(ORCHESTRATOR), f"Expected {ORCHESTRATOR} to exist."
    assert os.path.isfile(TEST_SUITE), f"Expected {TEST_SUITE} to exist."
    assert os.path.isfile(BINARY), f"Expected compiled Rust binary at {BINARY}."
    assert os.access(BINARY, os.X_OK), f"Expected {BINARY} to be executable."

    with open(ORCHESTRATOR, "r", encoding="utf-8") as f:
        orchestrator_source = f.read()
    for required in ("ops.dat", "encoded_ops.rs", "cargo", "build"):
        assert required in orchestrator_source, f"Orchestrator is missing required build logic: {required}"

    with open(TEST_SUITE, "r", encoding="utf-8") as f:
        test_source = f.read()
    assert "hypothesis" in test_source.lower(), "test_cli.py must use Hypothesis."
    assert re.search(r"@\s*(?:hypothesis\.)?(?:given|given\s*\()", test_source) or "@given" in test_source, \
        "test_cli.py must contain Hypothesis @given tests."
    assert "8080" in test_source and "200" in test_source, "test_cli.py must set up the telemetry mock on port 8080."
    assert "42" in test_source and "15" in test_source, "Property tests must check the decoded constants."

    with open(ENCODED, "r", encoding="utf-8") as f:
        encoded_source = f.read()
    assert "pub fn apply_op" in encoded_source, "Missing pub fn apply_op in generated Rust file."
    assert "match" in encoded_source, "Missing match statement in generated Rust file."
    assert "42" in encoded_source, "Missing constant 42 in generated Rust file."
    assert "15" in encoded_source, "Missing constant 15 in generated Rust file."


def check_original_binary_behavior():
    server, thread = start_server()
    try:
        invoke_binary(1, 10, 52)
        invoke_binary(2, 20, 5)
        invoke_binary(99, -321, -321)
        assert len(TelemetryHandler.requests_seen) >= 3
        assert all(path == "/log" for path in TelemetryHandler.requests_seen)
    finally:
        stop_server(server, thread)


def check_dynamic_orchestration():
    with open(OPS, "rb") as f:
        original_ops = f.read()

    add_const = secrets.randbelow(15000) + 1000
    sub_const = secrets.randbelow(15000) + 1000
    add_id = secrets.randbelow(100) + 20
    sub_id = secrets.randbelow(100) + 140
    while sub_id == add_id:
        sub_id = secrets.randbelow(100) + 140

    dynamic_ops = struct.pack("<BBh", add_id, 0, add_const) + struct.pack("<BBh", sub_id, 1, sub_const)

    cargo_dir = tempfile.mkdtemp(prefix="verifier-cargo-")
    cargo_marker = os.path.join(cargo_dir, "called")
    cargo_wrapper = os.path.join(cargo_dir, "cargo")
    with open(cargo_wrapper, "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\nprintf 'called\\n' >> \"$CARGO_MARKER\"\nexec /usr/bin/cargo \"$@\"\n")
    os.chmod(cargo_wrapper, 0o755)

    try:
        with open(OPS, "wb") as f:
            f.write(dynamic_ops)
        if os.path.exists(ENCODED):
            os.remove(ENCODED)
        if os.path.exists(BINARY):
            os.remove(BINARY)

        env = os.environ.copy()
        env["PATH"] = cargo_dir + os.pathsep + env.get("PATH", "")
        env["CARGO_MARKER"] = cargo_marker
        run([sys.executable, ORCHESTRATOR], cwd=HOME, env=env, timeout=240)

        assert os.path.isfile(ENCODED), "Orchestrator did not regenerate encoded_ops.rs."
        assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Orchestrator did not build the executable."
        with open(BINARY, "rb") as f:
            assert f.read(4) == b"\x7fELF", "Built artifact is not an ELF executable."
        assert os.path.exists(cargo_marker), "Orchestrator did not invoke cargo from PATH."

        with open(ENCODED, "r", encoding="utf-8") as f:
            generated = f.read()
        assert "pub fn apply_op" in generated and "match" in generated
        assert len(re.findall(r"\bpub\s+fn\b", generated)) == 1, "Generated file must contain a single public function."
        assert str(add_const) in generated and str(sub_const) in generated, "Generated code did not reflect ops.dat."

        server, thread = start_server()
        try:
            samples = [-10000, -997, 0, 81, 10000]
            for value in samples:
                invoke_binary(add_id, value, value + add_const)
                invoke_binary(sub_id, value, value - sub_const)
            unknown = next(i for i in range(256) if i not in (add_id, sub_id))
            invoke_binary(unknown, 734, 734)
        finally:
            stop_server(server, thread)
    finally:
        with open(OPS, "wb") as f:
            f.write(original_ops)
        shutil.rmtree(cargo_dir, ignore_errors=True)

    # Restore the required final build from the original ops.dat using the submitted orchestrator.
    run([sys.executable, ORCHESTRATOR], cwd=HOME, timeout=240)
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF"


def check_property_suite_and_mock_server():
    # Port 8080 must be available before pytest; the submitted fixture must provide the server.
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        probe.bind(("127.0.0.1", 8080))
    except OSError as exc:
        raise AssertionError("Port 8080 is occupied before test_cli.py starts; mock fixture cannot be verified") from exc
    finally:
        probe.close()

    temp_dir = tempfile.mkdtemp(prefix="verifier-property-")
    real_binary = os.path.join(temp_dir, "real-rust-calc")
    call_log = os.path.join(temp_dir, "calls.log")
    os.replace(BINARY, real_binary)

    wrapper = '''#!/usr/bin/env python3
import sys
import urllib.request
op = int(sys.argv[1])
value = int(sys.argv[2])
try:
    response = urllib.request.urlopen("http://127.0.0.1:8080/log", timeout=2)
    if response.status != 200:
        raise RuntimeError("telemetry did not return 200")
except Exception as exc:
    print("telemetry mock unavailable: %s" % exc, file=sys.stderr)
    sys.exit(70)
with open(%r, "a", encoding="utf-8") as log:
    log.write("%%d\\t%%d\\n" %% (op, value))
if op == 1:
    print(value + 42)
elif op == 2:
    print(value - 15)
else:
    print(value)
''' % call_log

    try:
        with open(BINARY, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(BINARY, 0o755)
        result = subprocess.run(
            [sys.executable, "-m", "pytest", TEST_SUITE, "-q", "--tb=short"],
            cwd=HOME,
            capture_output=True,
            text=True,
            timeout=240,
        )
        assert result.returncode == 0, (
            f"Submitted pytest suite failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(call_log), "Property tests never invoked the CLI binary."
        values = {1: set(), 2: set()}
        with open(call_log, "r", encoding="utf-8") as f:
            for line in f:
                op_text, value_text = line.strip().split("\t")
                op, value = int(op_text), int(value_text)
                if op in values:
                    assert -10000 <= value <= 10000, "Hypothesis input was outside the required range."
                    values[op].add(value)
        assert len(values[1]) >= 10, "op_id 1 was not exercised over enough property-generated inputs."
        assert len(values[2]) >= 10, "op_id 2 was not exercised over enough property-generated inputs."
    finally:
        if os.path.exists(BINARY):
            os.remove(BINARY)
        os.replace(real_binary, BINARY)
        shutil.rmtree(temp_dir, ignore_errors=True)


def main():
    check_required_files_and_original_assertions()
    check_original_binary_behavior()
    check_dynamic_orchestration()
    check_original_binary_behavior()
    check_required_files_and_original_assertions()
    check_property_suite_and_mock_server()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
