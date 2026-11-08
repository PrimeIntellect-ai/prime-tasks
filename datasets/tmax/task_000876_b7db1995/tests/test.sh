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
import hashlib
import os
import re
import tarfile

import pytest
import requests

RELEASE_DIR = "/app/project_delta"
INCOMING_DIR = "/app/incoming"
PORT = 8888
BASE_URL = f"http://127.0.0.1:{PORT}"
EXPECTED_DATA = {
    "alpha.bin": b"\0" * 100,
    "beta.bin": b"\0" * 200,
}
EXPECTED_ARCHIVES = {
    "valid1.tar.gz": ("alpha.dat", EXPECTED_DATA["alpha.bin"]),
    "valid2.tar.gz": ("beta.dat", EXPECTED_DATA["beta.bin"]),
}
EXPECTED_HASHES = {
    name: hashlib.sha256(data).hexdigest()
    for name, data in EXPECTED_DATA.items()
}


def get_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


def read_manifest(content):
    records = {}
    lines = content.splitlines()
    assert lines, "SHA256SUMS is empty."
    for line in lines:
        match = re.fullmatch(r"([0-9a-fA-F]{64})\s+\*?([^\s]+)", line)
        assert match, f"Malformed SHA256SUMS line: {line!r}"
        digest, filename = match.groups()
        assert filename not in records, f"Duplicate SHA256SUMS entry for {filename}."
        records[filename] = digest.lower()
    return records


def test_release_directory_exists():
    assert os.path.isdir(RELEASE_DIR), f"Directory {RELEASE_DIR} does not exist. Did you transcribe the audio correctly?"


def test_source_archive_integrity_and_corrupt_archive_discarded():
    corrupt_path = os.path.join(INCOMING_DIR, "corrupt.tar.gz")
    assert not os.path.exists(corrupt_path), "The corrupted archive was not discarded."

    for archive_name, (member_name, expected_bytes) in EXPECTED_ARCHIVES.items():
        archive_path = os.path.join(INCOMING_DIR, archive_name)
        assert os.path.isfile(archive_path), f"Expected valid archive {archive_name} is missing."
        with tarfile.open(archive_path, "r:gz") as archive:
            members = [m for m in archive.getmembers() if m.isfile()]
            assert [m.name for m in members] == [member_name], f"Unexpected contents in {archive_name}."
            extracted = archive.extractfile(members[0])
            assert extracted is not None
            assert extracted.read() == expected_bytes, f"{archive_name} failed content integrity validation."

    for name in os.listdir(INCOMING_DIR):
        if name.endswith(".tar.gz"):
            path = os.path.join(INCOMING_DIR, name)
            with tarfile.open(path, "r:gz") as archive:
                for member in archive.getmembers():
                    if member.isfile():
                        extracted = archive.extractfile(member)
                        assert extracted is not None
                        extracted.read()


def test_extracted_files_exist_and_renamed():
    alpha_path = os.path.join(RELEASE_DIR, "alpha.bin")
    beta_path = os.path.join(RELEASE_DIR, "beta.bin")

    assert os.path.isfile(alpha_path), f"{alpha_path} does not exist."
    assert os.path.isfile(beta_path), f"{beta_path} does not exist."

    assert os.path.getsize(alpha_path) == 100, f"{alpha_path} has incorrect size."
    assert os.path.getsize(beta_path) == 200, f"{beta_path} has incorrect size."

    with open(alpha_path, "rb") as f:
        assert f.read() == EXPECTED_DATA["alpha.bin"], "alpha.bin does not match the valid archive content."
    with open(beta_path, "rb") as f:
        assert f.read() == EXPECTED_DATA["beta.bin"], "beta.bin does not match the valid archive content."

    regular_bins = sorted(
        name for name in os.listdir(RELEASE_DIR)
        if name.endswith(".bin") and not os.path.islink(os.path.join(RELEASE_DIR, name))
    )
    assert regular_bins == ["alpha.bin", "beta.bin"], f"Unexpected regular .bin files: {regular_bins}"
    assert not any(name.endswith(".dat") for name in os.listdir(RELEASE_DIR)), "Unrenamed .dat files remain in the release directory."


def test_latest_symlink():
    symlink_path = os.path.join(RELEASE_DIR, "latest.bin")
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."

    target = os.readlink(symlink_path)
    assert os.path.basename(target) == "beta.bin", f"{symlink_path} does not point to beta.bin (the largest file)."
    with open(symlink_path, "rb") as f:
        assert f.read() == EXPECTED_DATA["beta.bin"], "latest.bin does not resolve to the expected largest binary."


def test_sha256sums_file():
    sums_path = os.path.join(RELEASE_DIR, "SHA256SUMS")
    assert os.path.isfile(sums_path), f"{sums_path} does not exist."
    assert not os.path.islink(sums_path), "SHA256SUMS must be a regular file."

    alpha_path = os.path.join(RELEASE_DIR, "alpha.bin")
    beta_path = os.path.join(RELEASE_DIR, "beta.bin")

    expected_alpha_hash = get_sha256(alpha_path)
    expected_beta_hash = get_sha256(beta_path)

    with open(sums_path, "r") as f:
        content = f.read()

    assert expected_alpha_hash in content, "SHA256SUMS is missing the hash for alpha.bin."
    assert expected_beta_hash in content, "SHA256SUMS is missing the hash for beta.bin."
    assert read_manifest(content) == EXPECTED_HASHES, "SHA256SUMS does not exactly describe the valid archive outputs."

    stat = os.stat(sums_path)
    assert stat.st_ctime_ns > stat.st_mtime_ns, "SHA256SUMS does not show metadata consistent with atomic replacement of a completed temporary file."
    leftovers = [name for name in os.listdir(RELEASE_DIR) if "SHA256SUMS" in name and name != "SHA256SUMS"]
    assert not leftovers, f"Temporary manifest files remain: {leftovers}"


def test_http_server_sha256sums():
    try:
        response = requests.get(f"{BASE_URL}/SHA256SUMS", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP server on port {PORT}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 for /SHA256SUMS, got {response.status_code}"

    alpha_path = os.path.join(RELEASE_DIR, "alpha.bin")
    beta_path = os.path.join(RELEASE_DIR, "beta.bin")

    expected_alpha_hash = get_sha256(alpha_path)
    expected_beta_hash = get_sha256(beta_path)

    content = response.text
    assert expected_alpha_hash in content, "HTTP response for SHA256SUMS is missing the hash for alpha.bin."
    assert expected_beta_hash in content, "HTTP response for SHA256SUMS is missing the hash for beta.bin."
    assert read_manifest(content) == EXPECTED_HASHES, "HTTP served an incorrect manifest."
    with open(os.path.join(RELEASE_DIR, "SHA256SUMS"), "rb") as f:
        assert response.content == f.read(), "HTTP did not serve the release directory's SHA256SUMS file."


def test_http_server_latest_bin():
    try:
        response = requests.get(f"{BASE_URL}/latest.bin", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP server on port {PORT}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 for /latest.bin, got {response.status_code}"
    assert len(response.content) == 200, f"Expected /latest.bin to serve 200 bytes, got {len(response.content)} bytes."
    assert response.content == EXPECTED_DATA["beta.bin"], "/latest.bin did not serve the valid beta archive content."


def test_http_server_listens_on_all_interfaces():
    port_hex = f"{PORT:04X}"
    listeners = []
    for proc_path in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(proc_path, "r") as f:
            for line in list(f)[1:]:
                fields = line.split()
                address, listed_port = fields[1].split(":")
                if listed_port.upper() == port_hex and fields[3] == "0A":
                    listeners.append(address)
    assert any(set(address) == {"0"} for address in listeners), f"No all-interfaces listener found on TCP port {PORT}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
