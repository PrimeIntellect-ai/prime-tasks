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
import importlib.metadata
import importlib.util
import io
import os
import secrets
import subprocess
import sys

import pytest
import requests

URL = "http://127.0.0.1:9090/upload"
TOKEN = "s3cr3t_admin_t0k3n"
UPLOAD_DIR = "/app/uploads"


def test_setup_py_fixed_and_package_installs():
    setup_path = "/app/file_vault/setup.py"
    assert os.path.isfile(setup_path), f"File {setup_path} is missing."
    with open(setup_path, "r") as f:
        content = f.read()
    assert "flask" in content.lower(), f"The dependency 'flask' is missing in {setup_path}. Did you fix the typo?"
    assert "flsk" not in content.lower(), f"The typo 'flsk' is still present in {setup_path}."

    result = subprocess.run(
        [sys.executable, "-m", "pip", "install", "-e", "/app/file_vault"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, f"pip install -e /app/file_vault failed:\n{result.stdout}"
    dist = importlib.metadata.distribution("file_vault")
    requirements = [r.lower() for r in (dist.requires or [])]
    assert any(r.startswith("flask") for r in requirements), "Installed package does not declare Flask."
    assert not any(r.startswith("flsk") for r in requirements), "Installed package still declares the broken flsk dependency."


def test_recovered_token_file():
    token_path = "/home/user/evidence/recovered_token.txt"
    assert os.path.isfile(token_path), f"File {token_path} is missing."
    with open(token_path, "r") as f:
        content = f.read().strip()
    assert content == "s3cr3t_admin_t0k3n", f"The recovered token in {token_path} is incorrect."


def post_live(filename, content=b"dummy content", auth=None):
    headers = {}
    if auth is not None:
        headers["Authorization"] = auth
    try:
        return requests.post(
            URL,
            headers=headers,
            files={"file": (filename, content)},
            timeout=5,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")


def test_service_valid_upload():
    filename = "test.txt"
    content = b"dummy content"
    response = post_live(filename, content, f"Bearer {TOKEN}")
    assert response.status_code == 200, f"Expected HTTP 200 for valid upload, got {response.status_code}. Response: {response.text}"
    saved = os.path.join(UPLOAD_DIR, filename)
    assert os.path.isfile(saved), f"Valid upload was not saved at {saved}."
    with open(saved, "rb") as f:
        assert f.read() == content, "Saved upload content does not match the submitted content."


def test_service_invalid_auth():
    response = post_live("test.txt", b"dummy content", "Bearer wrongtoken")
    assert response.status_code == 401, f"Expected HTTP 401 for invalid auth, got {response.status_code}. Response: {response.text}"


def test_service_path_traversal_blocked():
    response = post_live("../../../etc/passwd", b"dummy content", f"Bearer {TOKEN}")
    assert response.status_code in (400, 403), f"Expected HTTP 400 or 403 for path traversal attempt, got {response.status_code}. Response: {response.text}"


def test_live_service_general_authentication_and_storage():
    suffix = secrets.token_hex(12)
    filename = f"upload_{suffix}.bin"
    content = secrets.token_bytes(73)
    destination = os.path.join(UPLOAD_DIR, filename)
    if os.path.exists(destination):
        os.unlink(destination)

    response = post_live(filename, content, f"Bearer {TOKEN}")
    assert response.status_code == 200, response.text
    assert os.path.isfile(destination), "The live service did not save the upload under /app/uploads/."
    with open(destination, "rb") as f:
        assert f.read() == content

    bad_tokens = [
        None,
        f"Bearer {secrets.token_urlsafe(24)}",
        TOKEN,
        f"bearer {TOKEN}",
        f"Bearer {TOKEN} extra",
    ]
    for index, auth in enumerate(bad_tokens):
        rejected_name = f"auth_reject_{suffix}_{index}.bin"
        rejected_path = os.path.join(UPLOAD_DIR, rejected_name)
        if os.path.exists(rejected_path):
            os.unlink(rejected_path)
        response = post_live(rejected_name, secrets.token_bytes(19), auth)
        assert response.status_code == 401, f"Authorization value {auth!r} returned {response.status_code}, not 401."
        assert not os.path.exists(rejected_path), "An unauthorized upload was saved."


def test_live_service_rejects_arbitrary_slash_names():
    suffix = secrets.token_hex(10)
    filenames = [
        f"directory_{suffix}/file.bin",
        f"../escape_{suffix}.bin",
        f"folder_{suffix}/../escape.bin",
        f"a/b/{suffix}.bin",
    ]
    for filename in filenames:
        response = post_live(filename, secrets.token_bytes(31), f"Bearer {TOKEN}")
        assert response.status_code == 400, f"Slash-containing filename {filename!r} returned {response.status_code}, not 400."


def test_vendored_server_artifact_itself_is_patched():
    server_path = "/app/file_vault/file_vault/server.py"
    assert os.path.isfile(server_path), f"File {server_path} is missing."
    module_name = f"file_vault_verified_{secrets.token_hex(8)}"
    spec = importlib.util.spec_from_file_location(module_name, server_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "app"), "Vendored server.py does not expose its Flask application."

    client = module.app.test_client()
    suffix = secrets.token_hex(10)
    filename = f"source_{suffix}.dat"
    content = secrets.token_bytes(47)
    destination = os.path.join(UPLOAD_DIR, filename)
    if os.path.exists(destination):
        os.unlink(destination)

    response = client.post(
        "/upload",
        headers={"Authorization": f"Bearer {TOKEN}"},
        data={"file": (io.BytesIO(content), filename)},
        content_type="multipart/form-data",
    )
    assert response.status_code == 200
    assert os.path.isfile(destination), "The vendored server did not save the file under /app/uploads/."
    with open(destination, "rb") as f:
        assert f.read() == content

    wrong = secrets.token_urlsafe(25)
    for auth in (None, f"Bearer {wrong}", TOKEN, f"Bearer {TOKEN} extra"):
        headers = {} if auth is None else {"Authorization": auth}
        response = client.post(
            "/upload",
            headers=headers,
            data={"file": (io.BytesIO(b"blocked"), f"blocked_{secrets.token_hex(6)}.dat")},
            content_type="multipart/form-data",
        )
        assert response.status_code == 401, f"Vendored server accepted malformed authorization {auth!r}."

    for filename in (f"dir_{suffix}/file", f"../{suffix}", f"x/../{suffix}"):
        response = client.post(
            "/upload",
            headers={"Authorization": f"Bearer {TOKEN}"},
            data={"file": (io.BytesIO(b"blocked"), filename)},
            content_type="multipart/form-data",
        )
        assert response.status_code == 400, f"Vendored server did not reject {filename!r} with HTTP 400."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
