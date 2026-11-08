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
import glob
import os
import secrets
import signal
import subprocess
import tarfile
import tempfile
import time

import pytest
import requests

URL = "http://127.0.0.1:8080/apply"
TOKEN = "Bearer k8s-operator-token-123"

VALID_YAML = """apiVersion: v1
kind: Deployment
metadata:
  name: test-app
spec:
  replicas: 4
"""

INVALID_YAML = """apiVersion: v1
kind: Deployment
metadata:
  name: bad-app
"""


def compiler_result(payload):
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as f:
        f.write(payload)
        path = f.name
    try:
        proc = subprocess.run(
            ["/app/manifest_compiler", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=5,
        )
        return proc.returncode, proc.stdout
    finally:
        os.unlink(path)


def post(payload, token=TOKEN):
    headers = {} if token is None else {"Authorization": token}
    try:
        return requests.post(URL, headers=headers, data=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to operator: {e}")


def archive_has_file(path, suffix, expected=None):
    try:
        with tarfile.open(path, "r:gz") as tar:
            for member in tar.getmembers():
                if member.isfile() and member.name.endswith(suffix):
                    if expected is None:
                        return True
                    extracted = tar.extractfile(member)
                    return extracted is not None and extracted.read() == expected
    except (tarfile.TarError, OSError):
        return False
    return False


def scheduler_pids():
    found = []
    for entry in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            data = open(entry, "rb").read().replace(b"\0", b" ")
            pid = int(entry.split("/")[2])
        except (OSError, ValueError):
            continue
        if b"/home/user/scheduler.sh" in data:
            found.append(pid)
    return found


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].upper().endswith(":1F90") and fields[3] == "0A":
                inodes.add(fields[9])
    pids = []
    for proc in glob.glob("/proc/[0-9]*"):
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.append(int(proc.split("/")[-1]))
                break
    return pids


def test_operator_is_compiled_c_program_and_is_the_listener():
    source = "/home/user/operator.c"
    binary = "/home/user/operator"
    assert os.path.isfile(source), f"Missing C source file {source}"
    assert os.path.isfile(binary), f"Missing compiled operator {binary}"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "operator is not an ELF executable"
    rebuilt = "/tmp/operator-rebuilt"
    proc = subprocess.run(["gcc", source, "-o", rebuilt], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert proc.returncode == 0, f"operator.c does not compile as C: {proc.stderr.decode(errors='replace')}"
    pids = listener_pids()
    assert pids, "No process is listening on port 8080"
    assert any(
        os.path.exists(f"/proc/{pid}/exe") and os.path.samefile(f"/proc/{pid}/exe", binary)
        for pid in pids
    ), "The process listening on port 8080 is not /home/user/operator"


def test_operator_valid_request():
    response = post(VALID_YAML)
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    assert response.text.strip() == "COMPILED:test-app:8", f"Unexpected response body: {response.text}"


def test_operator_unauthorized():
    response = post(VALID_YAML, None)
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for missing token, got {response.status_code}"


def test_operator_invalid_request():
    response = post(INVALID_YAML)
    assert response.status_code == 400, f"Expected HTTP 400 Bad Request for compiler failure, got {response.status_code}"


def test_dynamic_compiler_integration_and_exact_output():
    for replicas in (0, secrets.randbelow(40) + 7, secrets.randbelow(50) + 60):
        name = "audit-" + secrets.token_hex(7)
        payload = f"""apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    audit: dynamic
  name: {name}
spec:
  replicas: {replicas}
  template:
    metadata:
      name: pod-{name}
"""
        expected_rc, expected_body = compiler_result(payload)
        assert expected_rc == 0
        response = post(payload)
        assert response.status_code == 200
        assert response.content == expected_body, "Response was not the compiler's exact output"
        saved = f"/home/user/manifests/{name}.yaml"
        assert os.path.isfile(saved), f"Dynamic manifest was not saved as {saved}"
        with open(saved, "rb") as f:
            assert f.read() == payload.encode(), "Saved manifest is not the original request payload"


def test_arbitrary_invalid_manifests_and_wrong_nonempty_tokens():
    bad_payloads = [
        f"apiVersion: v1\nmetadata:\n  name: invalid-{secrets.token_hex(5)}\nspec:\n",
        f"apiVersion: v1\nmetadata:\n  name: invalid-{secrets.token_hex(5)}\nspec:\n  replicas: -{secrets.randbelow(20)+1}\n",
    ]
    for payload in bad_payloads:
        expected_rc, expected_body = compiler_result(payload)
        assert expected_rc != 0
        response = post(payload)
        assert response.status_code == 400
        assert response.content == expected_body, "Compiler failure output was not returned exactly"

    protected_name = "unauth-" + secrets.token_hex(7)
    protected = f"metadata:\n  name: {protected_name}\nspec:\n  replicas: 9\n"
    for wrong in ("Bearer wrong-token", TOKEN + "x", "bearer k8s-operator-token-123", "x"):
        response = post(protected, wrong)
        assert response.status_code == 401, f"Incorrect nonempty token {wrong!r} was accepted"
    assert not os.path.exists(f"/home/user/manifests/{protected_name}.yaml")


def test_manifest_saved():
    manifest_path = "/home/user/manifests/test-app.yaml"
    assert os.path.exists(manifest_path), f"Manifest was not saved to {manifest_path}"
    with open(manifest_path, "r") as f:
        content = f.read()
    assert "test-app" in content, "Saved manifest does not contain the expected content"


def test_scheduler_runs_backup_repeatedly():
    assert os.path.isfile("/home/user/backup.sh") and os.access("/home/user/backup.sh", os.X_OK)
    assert os.path.isfile("/home/user/scheduler.sh") and os.access("/home/user/scheduler.sh", os.X_OK)
    assert scheduler_pids(), "scheduler.sh is not running in the background"

    marker1 = "scheduler-" + secrets.token_hex(6) + ".txt"
    marker2 = "scheduler-" + secrets.token_hex(6) + ".txt"
    open("/home/user/manifests/" + marker1, "wb").write(b"first scheduler cycle")
    deadline = time.time() + 5
    while time.time() < deadline:
        if any(archive_has_file(p, marker1, b"first scheduler cycle") for p in glob.glob("/home/user/backups/backup_*.tar.gz")):
            break
        time.sleep(0.25)
    else:
        pytest.fail("scheduler did not create a backup containing the first marker")

    open("/home/user/manifests/" + marker2, "wb").write(b"second scheduler cycle")
    deadline = time.time() + 5
    while time.time() < deadline:
        if any(archive_has_file(p, marker2, b"second scheduler cycle") for p in glob.glob("/home/user/backups/backup_*.tar.gz")):
            break
        time.sleep(0.25)
    else:
        pytest.fail("scheduler did not run backup.sh repeatedly")


def test_backup_script_general_rotation_and_archive_contents():
    # Stop the already-verified scheduler to make direct rotation testing deterministic.
    for pid in scheduler_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.3)

    backup_dir = "/home/user/backups"
    os.makedirs(backup_dir, exist_ok=True)
    for path in glob.glob(os.path.join(backup_dir, "backup_*.tar.gz")):
        os.unlink(path)

    now = int(time.time())
    old_paths = []
    for age in (500, 400, 300, 200, 100):
        path = os.path.join(backup_dir, f"backup_{now-age}.tar.gz")
        with tarfile.open(path, "w:gz") as tar:
            pass
        os.utime(path, (now-age, now-age))
        old_paths.append(path)

    marker = "rotation-" + secrets.token_hex(8) + ".txt"
    marker_data = secrets.token_bytes(37)
    with open("/home/user/manifests/" + marker, "wb") as f:
        f.write(marker_data)

    proc = subprocess.run(["/home/user/backup.sh"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert proc.returncode == 0, f"backup.sh failed: {proc.stderr.decode(errors='replace')}"
    backups = glob.glob(os.path.join(backup_dir, "backup_*.tar.gz"))
    assert 1 <= len(backups) <= 3, f"Expected at most 3 backups, found {len(backups)}"
    assert not os.path.exists(old_paths[0]) and not os.path.exists(old_paths[1]), "backup.sh did not delete the oldest backups"
    latest_backup = max(backups, key=os.path.getmtime)
    assert archive_has_file(latest_backup, marker, marker_data), "Latest backup does not contain current manifest data"


def test_backups_created_and_rotated():
    backup_dir = "/home/user/backups"
    assert os.path.isdir(backup_dir), f"Backup directory {backup_dir} does not exist"
    backups = glob.glob(os.path.join(backup_dir, "backup_*.tar.gz"))
    assert len(backups) > 0, "No backups found in the backup directory"
    assert len(backups) <= 3, f"Expected at most 3 backups, found {len(backups)}"
    latest_backup = max(backups, key=os.path.getmtime)
    with tarfile.open(latest_backup, "r:gz") as tar:
        names = tar.getnames()
        has_manifest = any("test-app.yaml" in name for name in names)
        assert has_manifest, f"Manifest 'test-app.yaml' not found in backup {latest_backup}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
