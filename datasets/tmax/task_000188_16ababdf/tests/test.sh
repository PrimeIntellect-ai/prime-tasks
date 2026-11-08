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
import re
import subprocess
import tempfile
from pathlib import Path

import pytest
import requests

REPO_DIR = Path("/home/user/repo")
RAW_DIR = Path("/home/user/raw")
WAL_PATH = Path("/home/user/transactions.wal")
PACKER = Path("/app/packer")
SERVER_CODE = Path("/home/user/server.py")
SERVER_URL = "http://127.0.0.1:8000"

EXPECTED_RAW = {
    "approved_1.elf": b"\x7fELF some elf data",
    "approved_2.gcode": b"; comment\nG1 X10 Y10\n",
    "rejected_1.elf": b"\x7fELF some other elf data",
    "approved_invalid.txt": b"just some random text data",
}
EXPECTED_WAL = (
    "[2023-10-01 10:00:00] APPROVE approved_1.elf\n"
    "[2023-10-01 10:05:00] APPROVE rejected_1.elf\n"
    "[2023-10-01 10:10:00] REJECT rejected_1.elf\n"
    "[2023-10-01 10:15:00] APPROVE approved_2.gcode\n"
    "[2023-10-01 10:20:00] APPROVE approved_invalid.txt\n"
)
WAL_RE = re.compile(
    r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] (APPROVE|REJECT) (.+)$"
)
GCODE_RE = re.compile(r"^\s*(?:G0|G1|M104|M109)(?:\s|$)")


def valid_artifact(data):
    if data.startswith(b"\x7fELF"):
        return True
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return False
    lines = text.splitlines()
    if not lines or not (lines[0].startswith(";") or lines[0] == ""):
        return False
    return any(GCODE_RE.match(line) for line in lines[1:])


def derive_expected_files():
    final_actions = {}
    for line in WAL_PATH.read_text(encoding="utf-8").splitlines():
        match = WAL_RE.fullmatch(line)
        assert match is not None, f"Malformed WAL record: {line!r}"
        action, filename = match.groups()
        final_actions[filename] = action

    result = []
    for filename, action in final_actions.items():
        path = RAW_DIR / filename
        if action == "APPROVE" and path.is_file() and valid_artifact(path.read_bytes()):
            result.append(filename + ".pkg")
    return sorted(result)


def get(url):
    try:
        return requests.get(url, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to server at {url}: {exc}")


def test_inputs_and_required_artifacts_exist():
    assert WAL_PATH.read_text(encoding="utf-8") == EXPECTED_WAL, "The approval WAL was modified."
    assert sorted(p.name for p in RAW_DIR.iterdir()) == sorted(EXPECTED_RAW)
    for filename, expected in EXPECTED_RAW.items():
        assert (RAW_DIR / filename).read_bytes() == expected, f"Raw input {filename} was modified."
    assert PACKER.is_file() and os.access(PACKER, os.X_OK), "/app/packer is missing or not executable."
    assert SERVER_CODE.is_file(), "/home/user/server.py does not exist."


def test_repo_directory_contents():
    assert REPO_DIR.is_dir(), f"Directory {REPO_DIR} does not exist."
    files = sorted(os.listdir(REPO_DIR))
    expected_files = ["approved_1.elf.pkg", "approved_2.gcode.pkg"]
    assert files == expected_files, f"Expected files {expected_files} in {REPO_DIR}, but found {files}."
    assert files == derive_expected_files(), "Repository does not match WAL and signature filtering."


def test_packages_match_packer_output():
    for package_name in derive_expected_files():
        raw_name = package_name[:-4]
        raw_path = RAW_DIR / raw_name
        with tempfile.TemporaryDirectory() as temporary_directory:
            expected_path = Path(temporary_directory) / package_name
            completed = subprocess.run(
                [str(PACKER), "pack", str(raw_path), str(expected_path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                check=False,
            )
            assert completed.returncode == 0, f"Packer failed for {raw_name}: {completed.stderr!r}"
            assert expected_path.is_file(), f"Packer did not produce output for {raw_name}."
            expected = expected_path.read_bytes()

        independently_derived = b"PKGRV1" + bytes(byte ^ 0x42 for byte in raw_path.read_bytes())
        assert expected == independently_derived, "/app/packer was modified or produced invalid output."
        assert (REPO_DIR / package_name).read_bytes() == expected, (
            f"{package_name} is not the output of /app/packer for {raw_name}."
        )


def test_server_manifest():
    url = f"{SERVER_URL}/manifest"
    response = get(url)
    assert response.status_code == 200, f"Expected status 200 for /manifest, got {response.status_code}."
    try:
        manifest = response.json()
    except ValueError:
        pytest.fail("Response from /manifest is not valid JSON.")

    expected_manifest = ["approved_1.elf.pkg", "approved_2.gcode.pkg"]
    assert manifest == expected_manifest, f"Expected manifest {expected_manifest}, got {manifest}."
    assert manifest == derive_expected_files(), "Manifest does not match the curated repository."


def test_server_artifact_elf():
    filename = "approved_1.elf.pkg"
    url = f"{SERVER_URL}/artifact/{filename}"
    filepath = REPO_DIR / filename
    assert filepath.is_file(), f"Expected packed file {filepath} does not exist."
    expected_content = filepath.read_bytes()
    response = get(url)
    assert response.status_code == 200, f"Expected status 200 for {url}, got {response.status_code}."
    assert response.content == expected_content, f"Content from {url} does not match the file on disk."


def test_server_artifact_gcode():
    filename = "approved_2.gcode.pkg"
    url = f"{SERVER_URL}/artifact/{filename}"
    filepath = REPO_DIR / filename
    assert filepath.is_file(), f"Expected packed file {filepath} does not exist."
    expected_content = filepath.read_bytes()
    response = get(url)
    assert response.status_code == 200, f"Expected status 200 for {url}, got {response.status_code}."
    assert response.content == expected_content, f"Content from {url} does not match the file on disk."


def test_server_artifact_not_found():
    url = f"{SERVER_URL}/artifact/nonexistent_file.pkg"
    response = get(url)
    assert response.status_code == 404, f"Expected status 404 for missing file, got {response.status_code}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
