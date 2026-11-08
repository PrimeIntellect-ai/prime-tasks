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
import base64
import io
import json
import re
import subprocess
import tarfile
import zipfile
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
VIDEO = Path("/app/project_screencast.mp4")
CONFIG_FILE = Path("/home/user/packaging.conf")
PROJECT = Path("/home/user/messy_project")


def decoded_video_config():
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-show_entries", "format_tags",
            "-of", "json", str(VIDEO),
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    metadata = json.loads(result.stdout)
    tags = metadata.get("format", {}).get("tags", {})
    comment = next((v for k, v in tags.items() if k.lower() == "comment"), None)
    assert comment is not None, "Video has no comment metadata tag"
    try:
        return base64.b64decode(comment, validate=True)
    except Exception as exc:
        pytest.fail(f"Video comment is not valid base64: {exc}")


def config_mapping():
    assert CONFIG_FILE.is_file(), "/home/user/packaging.conf was not created"
    expected = decoded_video_config()
    actual = CONFIG_FILE.read_bytes()
    assert actual == expected, "packaging.conf is not the configuration decoded from the video comment"

    mapping = {}
    for line in actual.decode("utf-8").splitlines():
        if not line.strip():
            continue
        assert ":" in line, f"Invalid configuration line: {line!r}"
        kind, path = line.split(":", 1)
        assert kind not in mapping, f"Duplicate configuration entry for {kind}"
        mapping[kind] = path
    assert set(mapping) == {"ELF", "WAL", "GCODE"}, "Configuration must map ELF, WAL, and GCODE"
    return mapping


def classify_sources():
    found = {"ELF": [], "WAL": [], "GCODE": []}
    for path in PROJECT.rglob("*"):
        if not path.is_file():
            continue
        content = path.read_bytes()
        if content.startswith(b"\x7fELF"):
            found["ELF"].append((path.name, content))
        elif content[:4] in (b"\x37\x7f\x06\x82", b"\x37\x7f\x06\x83"):
            found["WAL"].append((path.name, content))
        else:
            has_m109 = b"M109" in content
            has_g1 = re.search(br"(?m)^\s*G1(?:\s|$)", content) is not None
            if has_m109 and has_g1:
                found["GCODE"].append((path.name, content))
    return found


def fetch_archive(kind, expected_basename):
    mapping = config_mapping()
    archive_path = Path(mapping[kind])
    assert archive_path.name == expected_basename, (
        f"The {kind} configuration does not name {expected_basename}"
    )
    assert archive_path.is_file(), f"Configured archive was not created: {archive_path}"

    url = f"{BASE_URL}/{expected_basename}"
    try:
        resp = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {url}: {exc}")
    assert resp.status_code == 200, f"Expected HTTP 200 for {url}, got {resp.status_code}"
    assert resp.content == archive_path.read_bytes(), (
        f"HTTP server is not serving the configured archive {archive_path}"
    )
    return resp.content


def assert_exact_members(actual, expected, kind):
    assert sorted(actual) == sorted(expected), (
        f"{kind} archive members do not exactly match the classified project files"
    )


def test_packaging_configuration_extracted_from_video():
    config_mapping()


def test_binaries_tar_gz():
    data = fetch_archive("ELF", "binaries.tar.gz")
    expected = classify_sources()["ELF"]
    assert len(expected) == 2, f"Expected 2 ELF source files, found {len(expected)}"
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
            members = [m for m in tar.getmembers() if m.isfile()]
            assert len(members) == 2, f"Expected 2 files in binaries.tar.gz, found {len(members)}"
            actual = []
            for member in members:
                assert "/" not in member.name, f"File {member.name} should be at the root of the archive"
                content = tar.extractfile(member).read()
                assert content.startswith(b"\x7fELF"), f"File {member.name} in binaries.tar.gz is not an ELF file"
                actual.append((member.name, content))
            assert_exact_members(actual, expected, "ELF")
    except tarfile.TarError as exc:
        pytest.fail(f"Failed to parse binaries.tar.gz as a valid tar.gz archive: {exc}")


def test_manufacturing_zip():
    data = fetch_archive("GCODE", "manufacturing.zip")
    expected = classify_sources()["GCODE"]
    assert len(expected) == 2, f"Expected 2 GCODE source files, found {len(expected)}"
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            members = [m for m in zf.infolist() if not m.is_dir()]
            assert len(members) == 2, f"Expected 2 files in manufacturing.zip, found {len(members)}"
            actual = []
            contents = []
            for member in members:
                assert "/" not in member.filename, f"File {member.filename} should be at the root of the archive"
                with zf.open(member) as f:
                    content = f.read()
                contents.append(content)
                actual.append((member.filename, content))

            has_doc = any(b"M109 S200" in c and b"G1 X10" in c for c in contents)
            has_img = any(b"M109 S210" in c and b"G1 X20" in c for c in contents)
            assert has_doc and has_img, "manufacturing.zip does not contain the expected GCODE file contents"
            assert_exact_members(actual, expected, "GCODE")
    except zipfile.BadZipFile as exc:
        pytest.fail(f"Failed to parse manufacturing.zip as a valid zip archive: {exc}")


def test_database_logs_tar_bz2():
    data = fetch_archive("WAL", "database_logs.tar.bz2")
    expected = classify_sources()["WAL"]
    assert len(expected) == 2, f"Expected 2 WAL source files, found {len(expected)}"
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:bz2") as tar:
            members = [m for m in tar.getmembers() if m.isfile()]
            assert len(members) == 2, f"Expected 2 files in database_logs.tar.bz2, found {len(members)}"
            actual = []
            contents = []
            for member in members:
                assert "/" not in member.name, f"File {member.name} should be at the root of the archive"
                content = tar.extractfile(member).read()
                contents.append(content)
                actual.append((member.name, content))

            has_log1 = any(c.startswith(b"\x37\x7f\x06\x82") for c in contents)
            has_log2 = any(c.startswith(b"\x37\x7f\x06\x83") for c in contents)
            assert has_log1 and has_log2, "database_logs.tar.bz2 does not contain the expected WAL file contents"
            assert_exact_members(actual, expected, "WAL")
    except tarfile.TarError as exc:
        pytest.fail(f"Failed to parse database_logs.tar.bz2 as a valid tar.bz2 archive: {exc}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
