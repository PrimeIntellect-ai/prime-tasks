#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import re
import socket
import subprocess
import urllib.error
import urllib.request
import pytest

PROJECT = "/home/user/qa_mock"
CONFIG = "/home/user/nginx.conf"
RESULT_FILE = "/home/user/test_result.json"
DIRECT_URL = "http://127.0.0.1:3000/encode"
PROXY_URL = "http://127.0.0.1:8080/v1/telemetry"
FIXED_PAYLOAD = {"text": "Project-X: Defend The Core!", "shift": 7}
FIXED_RESULT = "V3l2cXhsYS1FOiBLbG1sdWsgQW9sIEp2eWwh"


def expected_result(text, shift):
    shifted = []
    for char in text:
        if "a" <= char <= "z":
            shifted.append(chr((ord(char) - ord("a") + shift) % 26 + ord("a")))
        elif "A" <= char <= "Z":
            shifted.append(chr((ord(char) - ord("A") + shift) % 26 + ord("A")))
        else:
            shifted.append(char)
    raw = "".join(shifted).encode("utf-8")
    return base64.b64encode(raw).decode("ascii")


def post_json(url, payload):
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200 from {url}, got {response.status}"
            body = response.read().decode("utf-8")
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to {url}: {exc}")
    try:
        parsed = json.loads(body)
    except json.JSONDecodeError:
        pytest.fail(f"Response from {url} is not valid JSON: {body!r}")
    assert isinstance(parsed, dict), f"Response from {url} must be a JSON object"
    assert set(parsed) == {"result"}, f"Unexpected response schema from {url}: {parsed!r}"
    assert isinstance(parsed["result"], str), "The result field must be a string"
    return parsed, body


def listening_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table, "r") as handle:
            next(handle)
            for line in handle:
                fields = line.split()
                local = fields[1]
                state = fields[3]
                if int(local.rsplit(":", 1)[1], 16) == port and state == "0A":
                    found.add(fields[9])
    return found


def processes_owning_port(port):
    wanted = {f"socket:[{inode}]" for inode in listening_inodes(port)}
    owners = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in wanted:
                        owners.append(int(entry))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def proc_exe(pid):
    return os.path.realpath(f"/proc/{pid}/exe")


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as handle:
            return handle.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def test_project_and_live_process_types():
    assert os.path.isdir(PROJECT), f"Rust project directory missing: {PROJECT}"
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing"
    source_dir = os.path.join(PROJECT, "src")
    assert os.path.isdir(source_dir), "Rust src directory is missing"
    rust_sources = []
    for root, _, files in os.walk(source_dir):
        rust_sources.extend(os.path.join(root, name) for name in files if name.endswith(".rs"))
    assert rust_sources, "The project contains no Rust source files"

    metadata_run = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert metadata_run.returncode == 0, f"Invalid Cargo project: {metadata_run.stderr}"
    metadata = json.loads(metadata_run.stdout)
    bin_names = {
        target["name"]
        for package in metadata["packages"]
        for target in package["targets"]
        if "bin" in target.get("kind", [])
    }
    assert bin_names, "Cargo project has no executable target"
    target_dir = os.path.realpath(metadata["target_directory"])

    rust_owners = processes_owning_port(3000)
    assert rust_owners, "Rust API is not listening on 127.0.0.1:3000"
    matching_rust = []
    for pid in rust_owners:
        executable = proc_exe(pid)
        if executable.startswith(target_dir + os.sep) and os.path.basename(executable) in bin_names:
            matching_rust.append(executable)
    assert matching_rust, f"Port 3000 is not owned by a binary target from {PROJECT}"
    with open(matching_rust[0], "rb") as executable_file:
        assert executable_file.read(4) == b"\x7fELF", "The Rust service target is not an executable ELF artifact"

    nginx_owners = processes_owning_port(8080)
    assert nginx_owners, "Nginx proxy is not listening on 127.0.0.1:8080"
    assert any(os.path.basename(proc_exe(pid)) == "nginx" for pid in nginx_owners), "Port 8080 is not owned by Nginx"
    nginx_processes = []
    for entry in os.listdir("/proc"):
        if entry.isdigit():
            try:
                if os.path.basename(proc_exe(int(entry))) == "nginx":
                    nginx_processes.append(int(entry))
            except OSError:
                pass
    assert any(CONFIG in proc_cmdline(pid) for pid in nginx_processes), "Running Nginx was not started with /home/user/nginx.conf"


def test_nginx_configuration():
    assert os.path.isfile(CONFIG), f"Expected Nginx configuration not found at {CONFIG}"
    checked = subprocess.run(["nginx", "-t", "-c", CONFIG], capture_output=True, text=True, timeout=15)
    assert checked.returncode == 0, f"Nginx configuration is invalid: {checked.stdout}\n{checked.stderr}"
    with open(CONFIG, "r") as handle:
        config = re.sub(r"#.*", "", handle.read())
    assert re.search(r"listen\s+127\.0\.0\.1:8080\s*;", config), "Nginx must listen on 127.0.0.1:8080"
    assert "/v1/telemetry" in config, "Nginx configuration is missing /v1/telemetry"
    assert "http://127.0.0.1:3000/encode" in config, "Nginx does not proxy to the required Rust endpoint"
    assert re.search(r"pid\s+/home/user/[^;]+;", config), "Nginx pid path must be under /home/user"
    assert re.search(r"(?:error_log|access_log)\s+/home/user/[^;\s]+", config), "Nginx log paths must be under /home/user"
    assert re.search(r"[a-z_]+_temp_path\s+/home/user/[^;]+;", config), "Nginx temporary paths must be under /home/user"


def test_result_file_exists_and_correct():
    assert os.path.isfile(RESULT_FILE), f"Expected result file not found at {RESULT_FILE}"
    with open(RESULT_FILE, "r") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULT_FILE} does not contain valid JSON")
    assert "result" in data, "JSON response missing 'result' key"
    assert data["result"] == FIXED_RESULT, f"Expected result '{FIXED_RESULT}', but got '{data['result']}'"


def test_ports_listening():
    for port, service in [(3000, "Rust API"), (8080, "Nginx Proxy")]:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(1)
            result = sock.connect_ex(("127.0.0.1", port))
            assert result == 0, f"{service} is not listening on 127.0.0.1:{port}"


def test_nginx_proxy_functionality_original_case():
    response, _ = post_json(PROXY_URL, {"text": "abc", "shift": 1})
    assert response["result"] == "YmNk", f"Expected API result 'YmNk', got '{response['result']}'"


def test_fixed_request_matches_saved_response():
    direct, _ = post_json(DIRECT_URL, FIXED_PAYLOAD)
    proxied, proxy_body = post_json(PROXY_URL, FIXED_PAYLOAD)
    assert direct["result"] == FIXED_RESULT
    assert proxied["result"] == FIXED_RESULT
    with open(RESULT_FILE, "r") as handle:
        saved = json.load(handle)
    assert saved == proxied, "test_result.json does not contain the exact JSON response for the required request"
    assert json.loads(proxy_body) == saved


def test_general_caesar_cipher_through_api_and_proxy():
    seed = int.from_bytes(os.urandom(16), "big")
    rng = random.Random(seed)
    cases = [
        ("", 0),
        ("AaZz", 1),
        ("Keep punctuation: 1234!?", 26),
        ("Wrap XYZ xyz; café_日本", 29),
    ]
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_:,.!?/@#"
    for _ in range(12):
        length = rng.randint(5, 90)
        text = "".join(rng.choice(alphabet) for _ in range(length))
        text += f"-{seed:x}"
        cases.append((text, rng.randint(0, 500)))

    for text, shift in cases:
        payload = {"text": text, "shift": shift}
        expected = expected_result(text, shift)
        direct, _ = post_json(DIRECT_URL, payload)
        proxied, _ = post_json(PROXY_URL, payload)
        assert direct["result"] == expected, f"Incorrect direct API result for {payload!r}"
        assert proxied["result"] == expected, f"Incorrect proxied result for {payload!r}"
        assert proxied == direct, "Nginx did not preserve the Rust API response"


def test_rust_project_builds():
    built = subprocess.run(
        ["cargo", "build", "--offline", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert built.returncode == 0, f"Rust project does not build offline:\n{built.stdout}\n{built.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
