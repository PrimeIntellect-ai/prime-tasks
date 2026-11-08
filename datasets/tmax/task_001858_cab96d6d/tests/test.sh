#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.metadata
import importlib.machinery
import os
from pathlib import Path
import secrets
import string
import subprocess
import sys
import time
import tomllib

import pytest
import requests

SERVER = "/app/server.py"
PACKAGE_DIR = Path("/app/vendored/ci-log-decoder")
URL = "http://127.0.0.1:8181/parse"


def stop_existing_servers():
    current = os.getpid()
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit() or int(entry.name) == current:
            continue
        try:
            cmdline = (entry / "cmdline").read_bytes().replace(b"\0", b" ")
            if b"/app/server.py" in cmdline:
                os.kill(int(entry.name), 15)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.5)


def wait_for_server(proc):
    last_error = None
    for _ in range(30):
        if proc.poll() is not None:
            pytest.fail(f"/app/server.py exited early with status {proc.returncode}")
        try:
            requests.get("http://127.0.0.1:8181", timeout=0.3)
            return
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(0.2)
    pytest.fail(f"Server did not start on 127.0.0.1:8181: {last_error}")


@pytest.fixture(scope="session")
def running_server():
    stop_existing_servers()
    proc = subprocess.Popen(
        [sys.executable, SERVER],
        cwd="/app",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    wait_for_server(proc)
    yield proc
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def test_server_file_exists():
    assert os.path.isfile("/app/server.py"), "The server script /app/server.py does not exist."


def test_build_configuration_and_rust_source():
    pyproject = PACKAGE_DIR / "pyproject.toml"
    rust_source = PACKAGE_DIR / "src/lib.rs"
    assert pyproject.is_file(), "Missing pyproject.toml"
    assert rust_source.is_file(), "Missing src/lib.rs"

    config = tomllib.loads(pyproject.read_text())
    build = config.get("build-system", {})
    assert build.get("build-backend") == "maturin", "pyproject.toml must use the maturin build backend"
    assert any(str(req).split(";")[0].strip().lower().startswith("maturin") for req in build.get("requires", [])), \
        "pyproject.toml build requirements must include maturin"

    result = subprocess.run(
        ["cargo", "check", "--offline"],
        cwd=PACKAGE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"Rust package does not compile offline:\n{result.stdout}"


def test_package_is_installed_native_extension_and_decodes():
    import ci_log_decoder

    assert importlib.metadata.version("ci-log-decoder"), "ci-log-decoder distribution is not installed"
    origin = getattr(ci_log_decoder, "__file__", "") or ""
    assert any(origin.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f"ci_log_decoder is not a compiled Python extension: {origin}"
    assert callable(getattr(ci_log_decoder, "decode_log", None)), "decode_log is not exported"

    alphabet = string.ascii_letters + string.digits
    messages = [
        "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(24) + 1))
        for _ in range(5)
    ]
    payload = b"".join(b"\x02" + bytes([len(msg.encode())]) + msg.encode() + b"\x03" for msg in messages)
    assert ci_log_decoder.decode_log(payload) == messages
    assert ci_log_decoder.decode_log(b"") == []
    with pytest.raises(ValueError):
        ci_log_decoder.decode_log(b"\x02\x05bad")


def test_server_source_imports_and_calls_decoder():
    tree = ast.parse(Path(SERVER).read_text(), filename=SERVER)
    module_bindings = set()
    function_bindings = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "ci_log_decoder":
                    module_bindings.add(alias.asname or "ci_log_decoder")
        elif isinstance(node, ast.ImportFrom) and node.module == "ci_log_decoder":
            for alias in node.names:
                if alias.name == "decode_log":
                    function_bindings.add(alias.asname or "decode_log")

    calls_decoder = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute) and node.func.attr == "decode_log":
            if isinstance(node.func.value, ast.Name) and node.func.value.id in module_bindings:
                calls_decoder = True
        elif isinstance(node.func, ast.Name) and node.func.id in function_bindings:
            calls_decoder = True

    assert module_bindings or function_bindings, "/app/server.py must import ci_log_decoder"
    assert calls_decoder, "/app/server.py must call ci_log_decoder.decode_log"


def test_server_parse_endpoint(running_server):
    # Original fixed normal-log assertion.
    payload = b'\x02\x05ERROR\x03\x02\x04WARN\x03'
    try:
        response = requests.post(URL, data=payload, headers={'Content-Type': 'application/octet-stream'}, timeout=3)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the parsing service at 127.0.0.1:8181.")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    assert response.headers.get('Content-Type', '').startswith('application/json'), "Expected Content-Type: application/json"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data == ["ERROR", "WARN"], f"Expected parsed output ['ERROR', 'WARN'], got {data}"

    # Original empty-log assertion.
    response_empty = requests.post(URL, data=b'', timeout=3)
    assert response_empty.status_code == 200, "Expected status code 200 for empty payload"
    assert response_empty.json() == [], f"Expected empty list for empty payload, got {response_empty.json()}"


def test_server_randomized_payloads(running_server):
    alphabet = string.ascii_letters + string.digits
    for _ in range(6):
        expected = [
            "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(35) + 1))
            for _ in range(secrets.randbelow(5) + 1)
        ]
        payload = b"".join(
            b"\x02" + bytes([len(message.encode("utf-8"))]) + message.encode("utf-8") + b"\x03"
            for message in expected
        )
        response = requests.post(
            URL,
            data=payload,
            headers={"Content-Type": "application/octet-stream"},
            timeout=3,
        )
        assert response.status_code == 200
        assert response.headers.get("Content-Type", "").startswith("application/json")
        assert response.json() == expected


def test_server_dynamically_delegates_bytes_to_ci_log_decoder(running_server, tmp_path):
    # Restart with an injected module so a Python reimplementation or fixed-response
    # server cannot satisfy the requirement to call ci_log_decoder.decode_log.
    running_server.terminate()
    running_server.wait(timeout=3)

    marker = tmp_path / "called"
    shim_dir = tmp_path / "shim"
    shim_dir.mkdir()
    (shim_dir / "ci_log_decoder.py").write_text(
        "from pathlib import Path\n"
        "def decode_log(data):\n"
        "    if type(data) is not bytes:\n"
        "        raise TypeError('decode_log argument was not bytes')\n"
        f"    Path({str(marker)!r}).write_bytes(data)\n"
        "    return ['DELEGATED', data.hex()]\n"
    )

    env = os.environ.copy()
    env["PYTHONPATH"] = str(shim_dir) + os.pathsep + env.get("PYTHONPATH", "")
    proc = subprocess.Popen(
        [sys.executable, SERVER],
        cwd="/app",
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_server(proc)
        body = secrets.token_bytes(23)
        response = requests.post(URL, data=body, timeout=3)
        assert response.status_code == 200
        assert response.headers.get("Content-Type", "").startswith("application/json")
        assert response.json() == ["DELEGATED", body.hex()]
        assert marker.read_bytes() == body
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
