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
import re
import secrets
import subprocess
import time
import zipfile

import pytest
import requests

IMAGE = "/app/legacy_schema.png"
ARCHIVE = "/app/backup_configs.zip"
CONFIGS_DIR = pathlib.Path("/home/user/configs")
SERVER_DIR = pathlib.Path("/home/user/server")
EXPECTED_TOKEN = "X9F2B-88ZZ1"
EXPECTED_PORT = 9095


def schema_from_image():
    result = subprocess.run(
        ["tesseract", IMAGE, "stdout", "--psm", "6"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    token_match = re.search(r"MASTER_TOKEN\s*[:=]\s*([A-Z0-9-]+)", result.stdout, re.I)
    port_match = re.search(r"SERVICE_PORT\s*[:=]\s*(\d+)", result.stdout, re.I)
    assert token_match, f"Tesseract output did not contain MASTER_TOKEN: {result.stdout!r}"
    assert port_match, f"Tesseract output did not contain SERVICE_PORT: {result.stdout!r}"
    return token_match.group(1), int(port_match.group(1))


TOKEN, PORT = schema_from_image()
BASE_URL = f"http://127.0.0.1:{PORT}"


def valid_archive_configs():
    expected = {}
    invalid = set()
    with zipfile.ZipFile(ARCHIVE) as archive:
        for info in archive.infolist():
            if info.is_dir() or not info.filename.endswith(".conf.bak"):
                continue
            try:
                raw = archive.read(info)
            except (zipfile.BadZipFile, RuntimeError, EOFError, zlib_error()):
                invalid.add(info.filename)
                continue
            output_name = info.filename[:-len(".conf.bak")] + ".json"
            transformed = raw.replace(b"{{TOKEN_PLACEHOLDER}}", TOKEN.encode())
            expected[output_name] = transformed
    return expected, invalid


def zlib_error():
    import zlib
    return zlib.error


def wait_for_server(url, timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.25)
    return False


def listening_pids(port):
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            socket_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
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
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    pids.add(int(proc.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def test_schema_values_are_ocr_derived():
    # Preserve the original expected schema assertions while deriving values via tesseract.
    assert TOKEN == EXPECTED_TOKEN
    assert PORT == EXPECTED_PORT


def test_files_extracted_integrity_checked_renamed_and_transformed():
    assert CONFIGS_DIR.is_dir(), f"Directory {CONFIGS_DIR} does not exist."

    expected, invalid = valid_archive_configs()
    assert "corrupted.conf.bak" in invalid, "The known CRC-damaged archive member was not detected as invalid."

    actual_files = {
        str(path.relative_to(CONFIGS_DIR))
        for path in CONFIGS_DIR.rglob("*")
        if path.is_file()
    }
    assert actual_files == set(expected), (
        f"Extracted files do not exactly match the valid archive members: "
        f"expected {sorted(expected)}, got {sorted(actual_files)}"
    )
    assert not any(path.suffix == ".bak" for path in CONFIGS_DIR.rglob("*")), "Backup extensions remain."

    for relative_name, expected_bytes in expected.items():
        output = CONFIGS_DIR / relative_name
        actual_bytes = output.read_bytes()
        assert b"{{TOKEN_PLACEHOLDER}}" not in actual_bytes, f"Placeholder remains in {output}."
        assert TOKEN.encode() in actual_bytes, f"OCR-derived token is absent from {output}."
        assert json.loads(actual_bytes) == json.loads(expected_bytes), f"Unexpected transformed content in {output}."

    # Preserve the original explicit filename checks.
    router_file = CONFIGS_DIR / "router_A.json"
    switch_file = CONFIGS_DIR / "switch_B.json"
    assert router_file.is_file(), f"File {router_file} does not exist."
    assert switch_file.is_file(), f"File {switch_file} does not exist."
    router_content = router_file.read_text()
    assert EXPECTED_TOKEN in router_content
    assert "{{TOKEN_PLACEHOLDER}}" not in router_content
    assert not (CONFIGS_DIR / "corrupted.json").exists()


def test_running_listener_is_server_artifact():
    assert SERVER_DIR.is_dir(), f"Directory {SERVER_DIR} does not exist."
    rust_sources = list(SERVER_DIR.rglob("*.rs"))
    assert rust_sources, "No Rust source file exists under /home/user/server/."
    assert wait_for_server(f"{BASE_URL}/api/config/router_A.json"), f"Server is not reachable on port {PORT}."

    pids = listening_pids(PORT)
    assert pids, f"No process owns a listening socket on port {PORT}."
    valid_executables = []
    server_root = SERVER_DIR.resolve()
    for pid in pids:
        try:
            executable = pathlib.Path(os.readlink(f"/proc/{pid}/exe")).resolve()
            under_server = os.path.commonpath([str(server_root), str(executable)]) == str(server_root)
            if under_server and executable.read_bytes()[:4] == b"\x7fELF":
                valid_executables.append(executable)
        except (FileNotFoundError, PermissionError, ProcessLookupError, ValueError, OSError):
            pass
    assert valid_executables, "The listener is not a compiled ELF server artifact under /home/user/server/."


def test_server_router_a():
    response = requests.get(f"{BASE_URL}/api/config/router_A.json", timeout=2)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}."
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type application/json."
    data = response.json()
    assert data.get("device") == "router_A", f"Expected device router_A, got {data.get('device')}."
    assert data.get("auth") == EXPECTED_TOKEN, f"Expected auth {EXPECTED_TOKEN}, got {data.get('auth')}."


def test_server_switch_b():
    response = requests.get(f"{BASE_URL}/api/config/switch_B.json", timeout=2)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}."
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type application/json."
    data = response.json()
    assert data.get("device") == "switch_B", f"Expected device switch_B, got {data.get('device')}."
    assert data.get("auth") == EXPECTED_TOKEN, f"Expected auth {EXPECTED_TOKEN}, got {data.get('auth')}."


def test_server_reads_arbitrary_file_and_returns_exact_contents():
    filename = f"verifier_{secrets.token_hex(12)}.json"
    path = CONFIGS_DIR / filename
    payload = {
        "device": f"dynamic-{secrets.token_hex(8)}",
        "auth": secrets.token_urlsafe(20),
        "nested": {"value": secrets.randbits(48)},
    }
    raw = (json.dumps(payload, separators=(",", ":")) + "\n").encode()
    path.write_bytes(raw)
    try:
        response = requests.get(f"{BASE_URL}/api/config/{filename}", timeout=2)
        assert response.status_code == 200, f"Dynamic file request returned {response.status_code}."
        assert "application/json" in response.headers.get("Content-Type", "")
        assert response.content == raw, "Endpoint did not return the newly created file's exact contents."
    finally:
        path.unlink(missing_ok=True)


def test_server_corrupted_and_random_missing_are_404():
    response = requests.get(f"{BASE_URL}/api/config/corrupted.json", timeout=2)
    assert response.status_code == 404, f"Expected status 404 for corrupted.json, got {response.status_code}."
    random_missing = f"missing_{secrets.token_hex(12)}.json"
    response = requests.get(f"{BASE_URL}/api/config/{random_missing}", timeout=2)
    assert response.status_code == 404, f"Expected status 404 for an unknown file, got {response.status_code}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
