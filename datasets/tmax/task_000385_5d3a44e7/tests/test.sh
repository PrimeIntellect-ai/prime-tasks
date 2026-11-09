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
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import string
import subprocess
import time
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
ENDPOINT = f"{BASE_URL}/build-config"
SOURCE = Path("/home/user/server.go")
BINARY = "/tmp/submission-server"


def read_manifest():
    result = subprocess.run(
        ["tesseract", "/app/legacy_route_manifest.png", "stdout"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=True,
    )
    token_match = re.search(r"(?im)^\s*AuthToken\s*:\s*(\S+)\s*$", result.stdout)
    target_match = re.search(r"(?im)^\s*Target\s*:\s*(\S+)\s*$", result.stdout)
    assert token_match, f"Could not OCR AuthToken from manifest. OCR output: {result.stdout!r}"
    assert target_match, f"Could not OCR Target from manifest. OCR output: {result.stdout!r}"
    return token_match.group(1), target_match.group(1)


def kill_port_9090():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10:
                local = fields[1]
                state = fields[3]
                if local.rsplit(":", 1)[-1].upper() == "2382" and state == "0A":
                    inodes.add(fields[9])

    if not inodes:
        return

    for proc_dir in Path("/proc").iterdir():
        if not proc_dir.name.isdigit():
            continue
        fd_dir = proc_dir / "fd"
        try:
            fds = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd in fds:
            try:
                link = os.readlink(fd)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", link)
            if match and match.group(1) in inodes:
                try:
                    os.kill(int(proc_dir.name), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    time.sleep(0.3)


def wait_for_server(process):
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f"Compiled server exited early with status {process.returncode}")
        try:
            requests.post(ENDPOINT, timeout=0.25)
            return
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail(f"Compiled server did not start on 127.0.0.1:9090: {last_error}")


@pytest.fixture(scope="session", autouse=True)
def running_submission():
    auth_token, target = read_manifest()

    # Preserve the original assertion that the agent actually left a server running.
    try:
        initial = requests.post(
            ENDPOINT,
            headers={"Authorization": "Bearer wrong-token", "Content-Type": "application/json"},
            json={"service_name": "test"},
            timeout=2,
        )
    except requests.RequestException as exc:
        pytest.fail(f"Agent did not leave a server running at {ENDPOINT}: {exc}")
    assert initial.status_code == 401, (
        f"Expected the initially running server to return 401 for an invalid token, "
        f"got {initial.status_code}"
    )

    assert SOURCE.is_file(), "/home/user/server.go does not exist or is not a regular file"
    source = SOURCE.read_text(errors="replace")
    assert re.search(r'(?m)(?:\b([A-Za-z_]\w*)\s+)?"text/template"', source), (
        "server.go must import Go's text/template package"
    )
    import_match = re.search(r'(?m)(?:\b([A-Za-z_]\w*)\s+)?"text/template"', source)
    template_alias = import_match.group(1) or "template"
    assert re.search(rf"\b{re.escape(template_alias)}\.New\s*\(", source), (
        "server.go must construct a text/template template"
    )
    assert re.search(r"\.Execute(?:Template)?\s*\(", source), (
        "server.go must execute the text/template template"
    )
    assert "tesseract" in source.lower(), "server.go must invoke OCR using tesseract"
    assert "/app/legacy_route_manifest.png" in source, (
        "server.go must OCR /app/legacy_route_manifest.png"
    )
    assert auth_token not in source, "server.go hardcodes the OCR AuthToken instead of extracting it"
    assert target not in source, "server.go hardcodes the OCR Target instead of extracting it"

    build = subprocess.run(
        ["go", "build", "-o", BINARY, str(SOURCE)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert build.returncode == 0, f"server.go did not compile:\n{build.stdout}"

    kill_port_9090()
    process = subprocess.Popen(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    wait_for_server(process)

    yield auth_token, target

    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()


def expected_yaml(name, target):
    normalized = "".join(ch for ch in name.lower() if ch in string.ascii_lowercase + string.digits)
    return f"service: {normalized}\ntarget: {target}\nmanaged_by: automation_specialist"


def authorized_headers(token):
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def test_server_running_and_unauthorized(running_submission):
    response = requests.post(
        ENDPOINT,
        headers={"Authorization": "Bearer wrong-token", "Content-Type": "application/json"},
        json={"service_name": "test"},
        timeout=2,
    )
    assert response.status_code == 401, f"Expected status code 401 for invalid token, got {response.status_code}"


def test_authenticated_standardization_1(running_submission):
    token, target = running_submission
    payload = {"service_name": "API_Gateway-v2!"}
    response = requests.post(ENDPOINT, headers=authorized_headers(token), json=payload, timeout=2)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    expected = expected_yaml(payload["service_name"], target)
    assert response.text.strip() == expected, f"Response body did not match expected YAML.\nExpected:\n{expected}\nGot:\n{response.text.strip()}"


def test_authenticated_standardization_2(running_submission):
    token, target = running_submission
    payload = {"service_name": "  $$$$__WEIRD___NaMe  "}
    response = requests.post(ENDPOINT, headers=authorized_headers(token), json=payload, timeout=2)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    expected = expected_yaml(payload["service_name"], target)
    assert response.text.strip() == expected, f"Response body did not match expected YAML.\nExpected:\n{expected}\nGot:\n{response.text.strip()}"


def test_randomized_normalization(running_submission):
    token, target = running_submission
    alphabet = string.ascii_letters + string.digits + " _-!@#$%^&*()[]{}:;,.?/\\|+=~`"
    for _ in range(12):
        name = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(45) + 12))
        response = requests.post(
            ENDPOINT,
            headers=authorized_headers(token),
            json={"service_name": name},
            timeout=2,
        )
        assert response.status_code == 200, f"Expected 200 for randomized service name, got {response.status_code}"
        expected = expected_yaml(name, target)
        assert response.text.strip() == expected, (
            f"Randomized normalization failed for {name!r}. Expected {expected!r}, got {response.text!r}"
        )


def test_auth_header_must_be_exact(running_submission):
    token, _ = running_submission
    invalid_headers = [
        {},
        {"Authorization": token},
        {"Authorization": f"bearer {token}"},
        {"Authorization": f"Bearer  {token}"},
        {"Authorization": f"Bearer {token}x"},
    ]
    for extra in invalid_headers:
        headers = {"Content-Type": "application/json", **extra}
        response = requests.post(ENDPOINT, headers=headers, json={"service_name": "random"}, timeout=2)
        assert response.status_code == 401, f"Invalid Authorization header {extra!r} returned {response.status_code}"


def test_only_post_build_config_is_exposed(running_submission):
    token, _ = running_submission
    headers = authorized_headers(token)
    for method in ("GET", "PUT", "PATCH", "DELETE"):
        response = requests.request(method, ENDPOINT, headers=headers, timeout=2)
        assert response.status_code in (404, 405), f"{method} /build-config unexpectedly returned {response.status_code}"

    paths = ["/", "/health", "/build", "/build-config/", "/debug/pprof/", "/" + secrets.token_hex(12)]
    for path in paths:
        response = requests.post(BASE_URL + path, headers=headers, json={"service_name": "x"}, timeout=2)
        assert response.status_code == 404, f"Unexpected endpoint {path} returned {response.status_code}"


def test_listens_strictly_on_ipv4_loopback(running_submission):
    listeners = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        for line in Path(table).read_text().splitlines()[1:]:
            fields = line.split()
            if len(fields) >= 4 and fields[1].rsplit(":", 1)[-1].upper() == "2382" and fields[3] == "0A":
                listeners.append((table, fields[1].rsplit(":", 1)[0]))
    assert listeners == [("/proc/net/tcp", "0100007F")], (
        f"Port 9090 must listen strictly on 127.0.0.1; found {listeners}"
    )
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
