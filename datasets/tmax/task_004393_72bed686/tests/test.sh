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
import ast
import hashlib
import importlib.metadata
import io
import json
import os
import secrets
import time
import uuid
import zipfile

import pytest
import requests

BASE_URL = "http://127.0.0.1:8888/manifest"
INCOMING = "/home/user/datasets/incoming"


def get_manifest(archive):
    return requests.get(BASE_URL, params={"archive": archive}, timeout=5)


def zip_bytes(files, compression=zipfile.ZIP_DEFLATED):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=compression) as zf:
        for path, data in files.items():
            zf.writestr(path, data)
    return output.getvalue()


def publish_complete_file(name, data):
    """Create a complete file before generating the watched create event."""
    os.makedirs(INCOMING, exist_ok=True)
    staging = os.path.join("/home/user/datasets", ".verify-" + uuid.uuid4().hex)
    destination = os.path.join(INCOMING, name)
    with open(staging, "wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.link(staging, destination)
    os.unlink(staging)
    return destination


def wait_for_manifest(name, expected, timeout=12):
    deadline = time.time() + timeout
    last_status = None
    last_body = None
    while time.time() < deadline:
        try:
            response = get_manifest(name)
            last_status = response.status_code
            last_body = response.text
            if response.status_code == 200:
                try:
                    body = response.json()
                except ValueError:
                    body = None
                if body == expected:
                    return
        except requests.RequestException as exc:
            last_body = repr(exc)
        time.sleep(0.25)
    pytest.fail(
        f"Manifest for {name} did not become correct; "
        f"last status={last_status}, body={last_body!r}, expected={expected!r}"
    )


def test_watchdog_fixed_and_installed():
    events_py_path = "/app/watchdog-3.0.0/src/watchdog/events.py"
    assert os.path.exists(events_py_path), f"File {events_py_path} does not exist."
    with open(events_py_path, "r") as f:
        content = f.read()
    assert "import brokensystem_module" not in content, \
        "The deliberate bug 'import brokensystem_module' is still present."

    assert importlib.metadata.version("watchdog") == "3.0.0"
    import watchdog.events
    import watchdog.observers
    assert watchdog.events.FileSystemEvent is not None
    assert watchdog.observers.Observer is not None


def test_server_script_uses_watchdog_observer():
    script = "/home/user/dataset_server.py"
    assert os.path.isfile(script), f"Missing required server script {script}"
    with open(script, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=script)

    imports_watchdog = any(
        (isinstance(node, ast.Import) and any(a.name == "watchdog" or a.name.startswith("watchdog.") for a in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module and (node.module == "watchdog" or node.module.startswith("watchdog.")))
        for node in ast.walk(tree)
    )
    called_attributes = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    observer_constructed = any(
        isinstance(node, ast.Call)
        and (
            (isinstance(node.func, ast.Name) and node.func.id.endswith("Observer"))
            or (isinstance(node.func, ast.Attribute) and node.func.attr.endswith("Observer"))
        )
        for node in ast.walk(tree)
    )
    assert imports_watchdog, "dataset_server.py does not import watchdog"
    assert observer_constructed, "dataset_server.py does not construct a watchdog Observer"
    assert "schedule" in called_attributes and "start" in called_attributes, \
        "The watchdog observer must be scheduled and started"


def test_dataset_server_original_behavior():
    os.makedirs(INCOMING, exist_ok=True)

    valid_zip_path = os.path.join(INCOMING, "test_dataset.zip")
    with zipfile.ZipFile(valid_zip_path, "w") as zf:
        zf.writestr("a.txt", "hello")
        zf.writestr("b.txt", "world")

    bad_zip_path = os.path.join(INCOMING, "bad.zip")
    with open(bad_zip_path, "w") as f:
        f.write("This is not a valid zip file")

    time.sleep(2)

    try:
        response_valid = get_manifest("test_dataset.zip")
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the dataset server: {e}")

    assert response_valid.status_code == 200, \
        f"Expected status code 200 for valid zip, got {response_valid.status_code}"
    try:
        manifest = response_valid.json()
    except ValueError:
        pytest.fail("Response body is not valid JSON")

    expected_a_hash = hashlib.sha256(b"hello").hexdigest()
    expected_b_hash = hashlib.sha256(b"world").hexdigest()
    assert manifest.get("a.txt") == expected_a_hash, \
        f"Hash for a.txt is incorrect, got {manifest.get('a.txt')}"
    assert manifest.get("b.txt") == expected_b_hash, \
        f"Hash for b.txt is incorrect, got {manifest.get('b.txt')}"

    response_bad = get_manifest("bad.zip")
    assert response_bad.status_code == 404, \
        f"Expected status code 404 for bad zip, got {response_bad.status_code}"


def test_random_archives_are_detected_and_hashed():
    # Values and names are generated only when verification runs, preventing a
    # server from hardcoding the original two responses.
    for index in range(2):
        archive = f"verify-{uuid.uuid4().hex}.zip"
        files = {
            f"nested-{uuid.uuid4().hex}/blob-{index}.bin": secrets.token_bytes(137 + index * 59),
            f"notes/{uuid.uuid4().hex}.txt": secrets.token_bytes(43 + index),
            f"root-{uuid.uuid4().hex}.dat": secrets.token_bytes(211 + index * 17),
        }
        expected = {path: hashlib.sha256(data).hexdigest() for path, data in files.items()}

        # It must not claim an archive was processed before it exists.
        before = get_manifest(archive)
        assert before.status_code == 404

        publish_complete_file(archive, zip_bytes(files))
        wait_for_manifest(archive, expected)


def test_random_corrupt_archives_remain_unavailable():
    archive = f"corrupt-{uuid.uuid4().hex}.zip"
    internal = f"payload-{uuid.uuid4().hex}.bin"
    payload = secrets.token_bytes(96)
    valid = zip_bytes({internal: payload}, compression=zipfile.ZIP_STORED)

    position = valid.find(payload)
    assert position >= 0
    corrupt = bytearray(valid)
    corrupt[position + len(payload) // 2] ^= 0xFF

    # Confirm this is a structurally recognizable ZIP whose integrity check fails.
    with zipfile.ZipFile(io.BytesIO(corrupt), "r") as zf:
        assert zf.testzip() == internal

    publish_complete_file(archive, bytes(corrupt))
    time.sleep(2)
    for _ in range(4):
        response = get_manifest(archive)
        assert response.status_code == 404, \
            f"Corrupt archive unexpectedly returned {response.status_code}: {response.text!r}"
        time.sleep(0.25)

    missing = f"missing-{uuid.uuid4().hex}.zip"
    assert get_manifest(missing).status_code == 404
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
