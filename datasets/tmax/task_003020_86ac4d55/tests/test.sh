#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

import pytest
import requests

APP = "/home/user/app"
URL = "http://127.0.0.1:9000/api/matrix_pow"
DIRECT_URL = "http://127.0.0.1:8080/api/matrix_pow"


def expected_power(base, n):
    def multiply(a, b):
        return [
            [a[0][0] * b[0][0] + a[0][1] * b[1][0],
             a[0][0] * b[0][1] + a[0][1] * b[1][1]],
            [a[1][0] * b[0][0] + a[1][1] * b[1][0],
             a[1][0] * b[0][1] + a[1][1] * b[1][1]],
        ]

    result = [[1, 0], [0, 1]]
    base = [row[:] for row in base]
    while n:
        if n & 1:
            result = multiply(result, base)
        n >>= 1
        if n:
            base = multiply(base, base)
    return result


def post_matrix(url, payload, timeout=5):
    try:
        response = requests.post(
            url,
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=timeout,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {url}: {exc}")

    assert response.status_code == 200, (
        f"Expected status 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "result" in data, f"Response JSON missing 'result' key: {data}"
    return data


def listener_inodes(port):
    wanted = f"{port:04X}"
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    address, encoded_port = fields[1].rsplit(":", 1)
                    if encoded_port != wanted:
                        continue
                    # Require the IPv4 loopback address, including its tcp6 form.
                    if address not in ("0100007F", "0000000000000000FFFF00000100007F"):
                        continue
                    found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def socket_owners(inodes):
    owners = []
    targets = {f"socket:[{inode}]" for inode in inodes}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") in targets:
                        exe = os.readlink(f"/proc/{name}/exe")
                        owners.append((int(name), exe))
                        break
                except (FileNotFoundError, PermissionError, OSError):
                    continue
        except (FileNotFoundError, PermissionError):
            continue
    return owners


def test_startup_log():
    log_path = "/home/user/app/startup.log"
    assert os.path.isfile(log_path), f"Startup log missing at {log_path}"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "SERVICES_READY" in content, (
        f"Expected 'SERVICES_READY' in startup.log, found: {content}"
    )


def test_rust_project_builds_and_required_files_exist():
    for path in (
        f"{APP}/rust_api/Cargo.toml",
        f"{APP}/rust_api/src/main.rs",
        f"{APP}/rust_api/src/math.rs",
        f"{APP}/nginx.conf",
    ):
        assert os.path.isfile(path), f"Required artifact missing: {path}"

    result = subprocess.run(
        ["cargo", "check", "--offline", "--manifest-path", f"{APP}/rust_api/Cargo.toml"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"Rust project does not compile:\n{result.stdout}"


def test_real_rust_and_nginx_listeners_and_configuration():
    rust_inodes = listener_inodes(8080)
    nginx_inodes = listener_inodes(9000)
    assert rust_inodes, "Nothing is listening on 127.0.0.1:8080"
    assert nginx_inodes, "Nothing is listening on 127.0.0.1:9000"

    rust_owners = socket_owners(rust_inodes)
    nginx_owners = socket_owners(nginx_inodes)
    assert any(
        os.path.basename(exe).replace(" (deleted)", "") == "rust_api"
        and exe.startswith(f"{APP}/rust_api/target/")
        for _, exe in rust_owners
    ), f"Port 8080 is not owned by the built Rust API: {rust_owners}"
    assert any(
        os.path.basename(exe).replace(" (deleted)", "") == "nginx"
        for _, exe in nginx_owners
    ), f"Port 9000 is not owned by Nginx: {nginx_owners}"

    check = subprocess.run(
        ["nginx", "-t", "-c", f"{APP}/nginx.conf"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
    )
    assert check.returncode == 0, f"nginx.conf is invalid:\n{check.stdout}"

    with open(f"{APP}/nginx.conf") as handle:
        config = re.sub(r"#.*", "", handle.read())
    assert re.search(r"\blisten\s+127\.0\.0\.1:9000\b", config), (
        "nginx.conf must listen on 127.0.0.1:9000"
    )
    assert re.search(r"\blocation\s+(?:\^~\s+)?/api/", config), (
        "nginx.conf must contain a location for /api/ requests"
    )
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:8080(?:/)?\s*;", config), (
        "nginx.conf must proxy API requests to 127.0.0.1:8080"
    )


def test_nginx_proxy_and_matrix_pow():
    test_cases = [
        ({"matrix": [[2, 0], [0, 2]], "n": 3}, [[8, 0], [0, 8]]),
        ({"matrix": [[1, 1], [1, 0]], "n": 0}, [[1, 0], [0, 1]]),
        ({"matrix": [[1, 1], [1, 0]], "n": 5}, [[8, 5], [5, 3]]),
        ({"matrix": [[1, 1], [1, 0]], "n": 10}, [[89, 55], [55, 34]]),
    ]

    for payload, expected in test_cases:
        data = post_matrix(URL, payload)
        assert data["result"] == expected, (
            f"For payload {payload}, expected {expected} but got {data['result']}"
        )


def test_runtime_generated_general_cases_through_proxy():
    rng = random.SystemRandom()
    cases = []
    for _ in range(24):
        matrix = [[rng.randint(-3, 3), rng.randint(-3, 3)],
                  [rng.randint(-3, 3), rng.randint(-3, 3)]]
        n = rng.randint(0, 8)
        cases.append({"matrix": matrix, "n": n})

    for payload in cases:
        expected = expected_power(payload["matrix"], payload["n"])
        data = post_matrix(URL, payload)
        assert data["result"] == expected, (
            f"For generated payload {payload}, expected {expected} but got {data['result']}"
        )


def test_proxy_reaches_rust_backend_and_exponentiation_is_fast():
    rng = random.SystemRandom()
    signed_permutations = [
        [[0, 1], [1, 0]],
        [[0, -1], [1, 0]],
        [[1, 0], [0, -1]],
        [[-1, 0], [0, -1]],
    ]
    payload = {
        "matrix": rng.choice(signed_permutations),
        "n": rng.randint(1_000_000_000, 4_294_967_295),
    }
    expected = expected_power(payload["matrix"], payload["n"])

    direct = post_matrix(DIRECT_URL, payload, timeout=5)
    proxied = post_matrix(URL, payload, timeout=5)
    assert direct["result"] == expected, (
        f"Direct Rust backend returned {direct['result']}, expected {expected}"
    )
    assert proxied["result"] == expected, (
        f"Nginx-proxied response returned {proxied['result']}, expected {expected}"
    )
    assert proxied["result"] == direct["result"]
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
