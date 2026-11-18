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

reward=0
real_oracle="/tmp/capacity_oracle.real.$$"
log_file="/tmp/capacity_oracle.calls.$$"
cleanup() {
    if [ -e "$real_oracle" ]; then
        rm -f /app/capacity_oracle
        mv "$real_oracle" /app/capacity_oracle
        chmod +x /app/capacity_oracle
    fi
    echo "$reward" > /logs/verifier/reward.txt
}
trap cleanup EXIT

mv /app/capacity_oracle "$real_oracle"
touch "$log_file"
chmod 666 "$log_file"
cat > /app/capacity_oracle <<EOF
#!/bin/sh
printf '%s %s\n' "\$1" "\$2" >> "$log_file"
exec "$real_oracle" "\$@"
EOF
chmod 755 /app/capacity_oracle

export REAL_ORACLE="$real_oracle"
export ORACLE_CALL_LOG="$log_file"

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import socket
import subprocess
import tempfile
import time
from pathlib import Path

import pytest
import requests

REPO = "/home/user/vm-specs.git"
PROJECT = Path("/home/user/cap-server")
REAL_ORACLE = os.environ["REAL_ORACLE"]
CALL_LOG = os.environ["ORACLE_CALL_LOG"]
URL = "http://127.0.0.1:8080"


def oracle(ram, cpu):
    result = subprocess.run(
        [REAL_ORACLE, str(ram), str(cpu)],
        check=True,
        capture_output=True,
        text=True,
        timeout=5,
    )
    return result.stdout


def clear_calls():
    Path(CALL_LOG).write_text("")


def calls():
    return [line.strip() for line in Path(CALL_LOG).read_text().splitlines() if line.strip()]


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == "0A" and fields[1].split(":")[-1] == wanted:
                inodes.add(fields[9])
    found = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(int(proc.name))
        except (OSError, PermissionError):
            pass
    return found


def qemu_processes():
    result = {}
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            exe = os.path.realpath(proc / "exe")
            if os.path.basename(exe) != "qemu-system-x86_64":
                continue
            argv = (proc / "cmdline").read_bytes().split(b"\0")
            result[int(proc.name)] = [x.decode(errors="replace") for x in argv if x]
        except (OSError, PermissionError):
            pass
    return result


def kill_qemu():
    for pid in qemu_processes():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while qemu_processes() and time.time() < deadline:
        time.sleep(0.1)
    for pid in qemu_processes():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def assert_pair(argv, option, value):
    assert any(argv[i] == option and argv[i + 1] == value for i in range(len(argv) - 1)), \
        f"Expected {option} {value} in QEMU arguments: {argv}"


def test_git_repo_and_hook():
    assert os.path.exists(REPO), f"Bare git repository not found at {REPO}"
    assert os.path.isdir(os.path.join(REPO, "refs")), f"{REPO} does not look like a bare git repository"
    bare = subprocess.run(
        ["git", "-C", REPO, "rev-parse", "--is-bare-repository"],
        check=True, capture_output=True, text=True,
    )
    assert bare.stdout.strip() == "true"

    hook = os.path.join(REPO, "hooks", "pre-receive")
    assert os.path.exists(hook), f"pre-receive hook not found at {hook}"
    assert os.access(hook, os.X_OK), f"pre-receive hook at {hook} is not executable"


def test_rust_project_and_running_systemd_service():
    unit_locations = [
        Path("/home/user/.config/systemd/user/cap-server.service"),
        Path("/etc/systemd/user/cap-server.service"),
        Path("/usr/lib/systemd/user/cap-server.service"),
        Path("/lib/systemd/user/cap-server.service"),
    ]
    assert any(p.is_file() for p in unit_locations), "cap-server user systemd unit file was not found"

    result = subprocess.run(
        ["systemctl", "--user", "is-active", "cap-server"],
        capture_output=True, text=True, check=False,
        env=dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000"),
    )
    assert result.stdout.strip() == "active", "cap-server systemd user service is not active"

    assert (PROJECT / "Cargo.toml").is_file(), "Cargo.toml missing from Rust project"
    rust_sources = list((PROJECT / "src").glob("**/*.rs"))
    assert rust_sources, "No Rust source files found in cap-server/src"
    build = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "cargo", "build", "--offline"],
        cwd=PROJECT, capture_output=True, text=True, timeout=120,
    )
    assert build.returncode == 0, f"Rust project does not build successfully:\n{build.stderr}"

    pids = listener_pids(8080)
    assert pids, "No process is listening on port 8080"
    rust_listener = False
    for pid in pids:
        try:
            status = Path(f"/proc/{pid}/status").read_text()
            uid_line = next(line for line in status.splitlines() if line.startswith("Uid:"))
            assert int(uid_line.split()[1]) == 1000, "Capacity server is not running as user"
            exe = os.path.realpath(f"/proc/{pid}/exe")
            with open(f"/proc/{pid}/exe", "rb") as f:
                assert f.read(4) == b"\x7fELF", "Listening server is not a native executable"
            if exe.startswith(str(PROJECT / "target") + os.sep):
                rust_listener = True
        except (OSError, StopIteration):
            continue
    assert rust_listener, "Port 8080 is not owned by the Rust project's Cargo-built executable"


def test_http_verify_endpoint_uses_oracle_on_unpredictable_inputs():
    rng = secrets.SystemRandom()
    payloads = []
    for _ in range(4):
        payloads.append((rng.randint(64, 1900), rng.randint(1, 4)))
    for _ in range(4):
        payloads.append((rng.randint(5000, 15000), rng.randint(2, 12)))

    clear_calls()
    expected_calls = []
    saw_ok = saw_reject = False
    for ram, cpu in payloads:
        expected = oracle(ram, cpu)
        saw_ok |= expected.strip() == "OK"
        saw_reject |= expected.strip() == "REJECT"
        response = requests.post(
            URL + "/verify",
            json={"ram_mb": ram, "cpu_cores": cpu},
            timeout=5,
        )
        assert response.status_code == 200
        assert response.text == expected, \
            f"/verify did not return the oracle's exact stdout for {ram}, {cpu}"
        expected_calls.append(f"{ram} {cpu}")

    assert saw_ok and saw_reject, "Dynamic test set did not cover both oracle outcomes"
    recorded = calls()
    for item in expected_calls:
        assert item in recorded, f"/app/capacity_oracle was not invoked with {item}"

    malformed = requests.post(
        URL + "/verify", data="{not-json", headers={"Content-Type": "application/json"}, timeout=5
    )
    assert 400 <= malformed.status_code < 500, "Malformed JSON was not handled gracefully"
    assert requests.post(URL + "/verify", json={"ram_mb": 128, "cpu_cores": 1}, timeout=5).status_code == 200


def test_http_allocate_endpoint_and_real_qemu():
    rng = secrets.SystemRandom()
    rejected = (rng.randint(9000, 15000), rng.randint(2, 8))
    accepted = (rng.randint(96, 192), rng.randint(1, 4))
    assert oracle(*rejected).strip() == "REJECT"
    assert oracle(*accepted).strip() == "OK"

    kill_qemu()
    clear_calls()
    before = set(qemu_processes())
    response = requests.post(
        URL + "/allocate",
        json={"ram_mb": rejected[0], "cpu_cores": rejected[1]},
        timeout=5,
    )
    assert response.status_code == 400, f"Expected 400 for rejected allocation, got {response.status_code}"
    time.sleep(0.5)
    assert set(qemu_processes()) == before, "Rejected allocation started QEMU"
    assert f"{rejected[0]} {rejected[1]}" in calls(), "Rejected allocation did not invoke the oracle"

    clear_calls()
    response = requests.post(
        URL + "/allocate",
        json={"ram_mb": accepted[0], "cpu_cores": accepted[1]},
        timeout=5,
    )
    assert response.status_code == 200, f"Expected 200 for accepted allocation, got {response.status_code}"
    assert f"{accepted[0]} {accepted[1]}" in calls(), "Accepted allocation did not invoke the oracle"

    deadline = time.time() + 8
    new = {}
    while time.time() < deadline:
        new = {pid: argv for pid, argv in qemu_processes().items() if pid not in before}
        if new:
            break
        time.sleep(0.2)
    assert new, "Accepted allocation did not start qemu-system-x86_64"

    matched = False
    for argv in new.values():
        try:
            assert_pair(argv, "-m", str(accepted[0]))
            assert_pair(argv, "-smp", str(accepted[1]))
            assert_pair(argv, "-vnc", "127.0.0.1:1")
            assert "-daemonize" in argv
            matched = True
            break
        except AssertionError:
            pass
    assert matched, f"No QEMU process had the required allocation arguments: {new}"

    with socket.create_connection(("127.0.0.1", 5901), timeout=3) as sock:
        banner = sock.recv(4)
    assert banner == b"RFB ", "Port 5901 is not serving a QEMU VNC endpoint"


def test_git_push_behavior_for_added_and_modified_json():
    rng = secrets.SystemRandom()
    valid = (rng.randint(128, 1500), rng.randint(1, 4))
    invalid_add = (rng.randint(7000, 15000), rng.randint(2, 10))
    invalid_modify = (rng.randint(7000, 15000), rng.randint(2, 10))
    assert oracle(*valid).strip() == "OK"
    assert oracle(*invalid_add).strip() == "REJECT"
    assert oracle(*invalid_modify).strip() == "REJECT"
    branch = "audit-" + secrets.token_hex(6)

    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(["git", "clone", REPO, tmpdir], check=True, capture_output=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=tmpdir, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=tmpdir, check=True)
        subprocess.run(["git", "checkout", "--orphan", branch], cwd=tmpdir, check=True, capture_output=True)
        subprocess.run(["git", "rm", "-rf", "."], cwd=tmpdir, check=False, capture_output=True)

        Path(tmpdir, "valid.json").write_text(json.dumps({"ram_mb": valid[0], "cpu_cores": valid[1]}))
        subprocess.run(["git", "add", "valid.json"], cwd=tmpdir, check=True)
        subprocess.run(["git", "commit", "-m", "Add valid spec"], cwd=tmpdir, check=True, capture_output=True)
        clear_calls()
        push = subprocess.run(
            ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
            cwd=tmpdir, capture_output=True, text=True,
        )
        assert push.returncode == 0, f"Git push failed for valid JSON: {push.stderr}"
        assert f"{valid[0]} {valid[1]}" in calls(), "Hook did not submit added JSON to /verify"

        Path(tmpdir, "invalid.json").write_text(json.dumps({"ram_mb": invalid_add[0], "cpu_cores": invalid_add[1]}))
        subprocess.run(["git", "add", "invalid.json"], cwd=tmpdir, check=True)
        subprocess.run(["git", "commit", "-m", "Add invalid spec"], cwd=tmpdir, check=True, capture_output=True)
        clear_calls()
        push = subprocess.run(
            ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
            cwd=tmpdir, capture_output=True, text=True,
        )
        assert push.returncode != 0, "Git push succeeded for added invalid JSON"
        assert "REJECT" in push.stderr or "declined" in push.stderr
        assert f"{invalid_add[0]} {invalid_add[1]}" in calls(), "Hook did not submit added invalid JSON"

        subprocess.run(["git", "reset", "--hard", f"origin/{branch}"], cwd=tmpdir, check=True, capture_output=True)
        Path(tmpdir, "valid.json").write_text(json.dumps({"ram_mb": invalid_modify[0], "cpu_cores": invalid_modify[1]}))
        subprocess.run(["git", "add", "valid.json"], cwd=tmpdir, check=True)
        subprocess.run(["git", "commit", "-m", "Modify spec to invalid"], cwd=tmpdir, check=True, capture_output=True)
        clear_calls()
        push = subprocess.run(
            ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
            cwd=tmpdir, capture_output=True, text=True,
        )
        assert push.returncode != 0, "Git push succeeded for modified invalid JSON"
        assert "REJECT" in push.stderr or "declined" in push.stderr
        assert f"{invalid_modify[0]} {invalid_modify[1]}" in calls(), "Hook did not submit modified JSON to /verify"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
else
    reward=0
fi
