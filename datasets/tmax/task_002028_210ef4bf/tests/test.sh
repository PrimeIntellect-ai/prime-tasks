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
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import pwd
import signal
import subprocess
import time

import pytest
import requests

PROJECT = pathlib.Path("/home/user/forensics_api")
URL = "http://127.0.0.1:8181/recovered-data"
TOKEN = "Bearer forensics-auth-token"
SERVER_PROCESS = None


def decrypt_evidence():
    encrypted = "/app/evidence/payload.enc"
    assert os.path.isfile(encrypted), "Encrypted evidence is missing"

    for pin in range(10000):
        password = f"panther{pin:04d}"
        result = subprocess.run(
            [
                "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
                "-in", encrypted, "-pass", f"pass:{password}"
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode != 0:
            continue
        try:
            data = json.loads(result.stdout.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
        if isinstance(data, list) and all(isinstance(item, dict) for item in data):
            return data

    pytest.fail("Could not brute-force and decrypt payload.enc")


def expected_redacted_data():
    data = decrypt_evidence()
    result = []
    for original in data:
        assert {"id", "username", "ssn", "private_ssh_key"}.issubset(original), \
            "Decrypted payload has an unexpected structure"
        item = dict(original)
        item["ssn"] = "REDACTED_SSN"
        item["private_ssh_key"] = "REDACTED_KEY"
        result.append(item)
    return result


def find_bruteforce_artifact():
    roots = [pathlib.Path("/home/user"), PROJECT]
    seen = set()
    for root in roots:
        if not root.exists():
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {"target", ".git", ".cargo"}]
            for filename in files:
                path = pathlib.Path(directory) / filename
                try:
                    resolved = str(path.resolve())
                    if resolved in seen or path.stat().st_size > 1024 * 1024:
                        continue
                    seen.add(resolved)
                    raw = path.read_bytes()
                    text = raw.decode("utf-8", errors="ignore")
                except OSError:
                    continue

                lower = text.lower()
                has_payload = "payload.enc" in lower
                has_prefix = "panther" in lower
                has_crypto = "pbkdf2" in lower and ("openssl" in lower or "aes" in lower)
                has_pin_space = any(marker in lower for marker in (
                    "9999", "10000", "0000", "0..=9999", "0..10000"
                ))
                if not (has_payload and has_prefix and has_crypto and has_pin_space):
                    continue

                is_shell = path.suffix == ".sh" or raw.startswith(b"#!/bin/bash") or raw.startswith(b"#!/usr/bin/env bash")
                is_rust = path.suffix == ".rs" and str(path.resolve()).startswith(str(PROJECT.resolve()) + os.sep)
                if is_shell or is_rust:
                    return path, "shell" if is_shell else "rust"

    pytest.fail("No bash or Rust brute-force implementation for the four-digit PIN was found")


def run_shell_artifact(path):
    user = pwd.getpwnam("user")

    def demote():
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    result = subprocess.run(
        ["/bin/bash", str(path)],
        cwd=str(path.parent),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=240,
        preexec_fn=demote,
        env={**os.environ, "HOME": user.pw_dir, "USER": "user"},
    )
    assert result.returncode == 0, \
        f"Brute-force script failed when executed:\n{result.stdout.decode(errors='replace')[-2000:]}"


def cargo_binary():
    assert (PROJECT / "Cargo.toml").is_file(), "Cargo.toml is missing from the Rust project"
    rust_sources = list(PROJECT.rglob("*.rs"))
    rust_sources = [p for p in rust_sources if "target" not in p.parts]
    assert rust_sources, "The project contains no Rust source files"

    build = subprocess.run(
        ["cargo", "build", "--quiet"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=300,
    )
    assert build.returncode == 0, \
        f"Rust project did not compile:\n{build.stdout.decode(errors='replace')[-4000:]}"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert metadata_result.returncode == 0, "Unable to inspect Cargo project metadata"
    metadata = json.loads(metadata_result.stdout)

    bins = []
    for package in metadata["packages"]:
        for target in package.get("targets", []):
            if "bin" in target.get("kind", []):
                bins.append((package, target))

    assert bins, "Cargo project has no binary server target"
    if len(bins) > 1:
        defaults = [(p, t) for p, t in bins if p.get("default_run") == t.get("name")]
        assert len(defaults) == 1, "Cargo project has multiple binaries and no unique default server"
        package, target = defaults[0]
    else:
        package, target = bins[0]

    executable = pathlib.Path(metadata["target_directory"]) / "debug" / target["name"]
    assert executable.is_file() and os.access(executable, os.X_OK), "Compiled Rust server executable is missing"
    with executable.open("rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Cargo output is not a native executable"
    return executable


def kill_port_8181_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].split(":")[-1].upper() == "1FF5" and fields[3] == "0A":
                inodes.add(fields[9])

    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    os.kill(int(proc.name), signal.SIGKILL)
                    break
        except (OSError, PermissionError):
            pass
    time.sleep(0.5)


def listener_is_exact_process(pid):
    expected_inode = None
    try:
        for line in pathlib.Path("/proc/net/tcp").read_text().splitlines()[1:]:
            fields = line.split()
            if len(fields) >= 10 and fields[1].upper() == "0100007F:1FF5" and fields[3] == "0A":
                expected_inode = fields[9]
                break
    except OSError:
        return False
    if expected_inode is None:
        return False

    try:
        for fd in (pathlib.Path("/proc") / str(pid) / "fd").iterdir():
            try:
                if os.readlink(fd) == f"socket:[{expected_inode}]":
                    return True
            except OSError:
                pass
    except OSError:
        return False
    return False


@pytest.fixture(scope="session", autouse=True)
def prepared_server():
    global SERVER_PROCESS

    assert PROJECT.is_dir(), "Rust project directory /home/user/forensics_api does not exist."
    artifact, kind = find_bruteforce_artifact()
    if kind == "shell":
        run_shell_artifact(artifact)

    executable = cargo_binary()
    if kind == "rust":
        binary_strings = subprocess.run(
            ["strings", str(executable)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
        ).stdout.decode(errors="ignore").lower()
        assert "payload.enc" in binary_strings and "panther" in binary_strings, \
            "The Rust brute-force implementation is not part of the compiled server"

    kill_port_8181_listeners()
    log = open("/tmp/forensics_api.log", "wb")
    SERVER_PROCESS = subprocess.Popen(
        [str(executable)],
        cwd=PROJECT,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )

    deadline = time.time() + 120
    while time.time() < deadline:
        if SERVER_PROCESS.poll() is not None:
            log.flush()
            output = pathlib.Path("/tmp/forensics_api.log").read_text(errors="replace")
            pytest.fail(f"Compiled Rust server exited before serving requests:\n{output[-4000:]}")
        try:
            requests.get(URL, timeout=0.5)
            break
        except requests.exceptions.RequestException:
            time.sleep(0.25)
    else:
        pytest.fail("Compiled Rust server did not start on 127.0.0.1:8181")

    assert listener_is_exact_process(SERVER_PROCESS.pid), \
        "The compiled Rust process itself must listen exactly on 127.0.0.1:8181"
    yield


def test_rust_project_exists():
    assert os.path.isdir("/home/user/forensics_api"), \
        "Rust project directory /home/user/forensics_api does not exist."


def test_api_unauthorized():
    response = requests.get(URL, timeout=2)
    assert response.status_code == 401, \
        f"Expected status code 401 for unauthorized request, got {response.status_code}"

    wrong = requests.get(URL, headers={"Authorization": "Bearer wrong-token"}, timeout=2)
    assert wrong.status_code == 401, \
        f"Expected status code 401 for an invalid Bearer token, got {wrong.status_code}"


def test_api_authorized_and_redacted():
    response = requests.get(URL, headers={"Authorization": TOKEN}, timeout=2)
    assert response.status_code == 200, \
        f"Expected status code 200 for authorized request, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response body is not valid JSON")

    expected_data = expected_redacted_data()
    assert isinstance(data, list), "Expected response JSON to be a list"
    assert len(data) == len(expected_data), \
        f"Expected {len(expected_data)} items in the response list, got {len(data)}"
    for item in expected_data:
        assert item in data, f"Expected item {item} not found in response data"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
