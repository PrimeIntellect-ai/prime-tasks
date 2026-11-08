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
import io
import os
import signal
import subprocess
import tarfile
from pathlib import Path

import pytest
import requests

AUTH_TOKEN = "secr3t_lab_77xyz"
BASE_URL = "http://127.0.0.1:8000"
RAW_PATH = Path("/home/user/raw_sensor.bin")
ARCHIVE_PATH = Path("/home/user/recovered.tar.gz")
DATASET_DIR = Path("/home/user/dataset")
MAGIC = bytes.fromhex("DE AD BE EF")


def recover_expected():
    raw = RAW_PATH.read_bytes()
    output = bytearray()
    pos = 0
    chunks = 0
    while True:
        start = raw.find(MAGIC, pos)
        if start < 0:
            break
        assert start + 8 <= len(raw), "Truncated chunk size after magic header"
        size = int.from_bytes(raw[start + 4:start + 8], "little")
        end = start + 8 + size
        assert end <= len(raw), "Chunk payload extends beyond raw_sensor.bin"
        output.extend(raw[start + 8:end])
        chunks += 1
        pos = end
    assert chunks > 0, "No valid chunks found in raw_sensor.bin"
    return bytes(output)


@pytest.fixture(scope="session")
def expected_archive():
    return recover_expected()


@pytest.fixture(scope="session")
def expected_files(expected_archive):
    result = {}
    with tarfile.open(fileobj=io.BytesIO(expected_archive), mode="r:gz") as archive:
        members = archive.getmembers()
        assert members, "Recovered archive contains no members"
        for member in members:
            if not member.isfile():
                continue
            name = member.name
            while name.startswith("./"):
                name = name[2:]
            assert name and not name.startswith("/") and ".." not in Path(name).parts
            extracted = archive.extractfile(member)
            assert extracted is not None
            original = extracted.read()
            cleaned = original.replace(b"[ERR_CALIBRATION_LOSS]", b"NaN")
            cleaned = cleaned.replace(b"SENSOR_NODE_00", b"NODE_0")
            result[name] = cleaned
    assert result, "Recovered archive contains no regular files"
    return result


def cpp_sources():
    sources = []
    for root in (Path("/home/user"), Path("/app"), Path("/tmp")):
        if root.exists():
            for pattern in ("*.cpp", "*.cc", "*.cxx", "*.C"):
                sources.extend(root.rglob(pattern))
    return [p for p in sources if p.is_file()]


def elf_executables():
    found = []
    for root in (Path("/home/user"), Path("/app")):
        if not root.exists():
            continue
        for path in root.rglob("*"):
            try:
                if path.is_file() and os.access(path, os.X_OK):
                    with path.open("rb") as f:
                        if f.read(4) == b"\x7fELF":
                            found.append(path)
            except OSError:
                pass
    return found


def run_candidate(path):
    proc = subprocess.Popen(
        [str(path)], cwd="/home/user", stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=1)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def test_01_cpp_recovery_program_executes(expected_archive):
    sources = cpp_sources()
    assert sources, "No C++ source file was written"
    source_text = "\n".join(
        p.read_text(encoding="utf-8", errors="ignore") for p in sources
    )
    assert "raw_sensor.bin" in source_text, "C++ source does not implement raw sensor recovery"
    assert "recovered.tar.gz" in source_text, "C++ source does not produce recovered.tar.gz"
    assert "Authorization" in source_text and "8000" in source_text, \
        "C++ source does not implement the required authenticated HTTP server"

    candidates = []
    for path in elf_executables():
        try:
            data = path.read_bytes()
        except OSError:
            continue
        if b"raw_sensor.bin" in data and b"recovered.tar.gz" in data:
            candidates.append(path)
    assert candidates, "No compiled C++ recovery executable was found"

    original = ARCHIVE_PATH.read_bytes() if ARCHIVE_PATH.is_file() else None
    succeeded = False
    for candidate in candidates:
        try:
            ARCHIVE_PATH.unlink(missing_ok=True)
            run_candidate(candidate)
            if ARCHIVE_PATH.is_file() and ARCHIVE_PATH.read_bytes() == expected_archive:
                succeeded = True
                break
        except OSError:
            continue
    if not succeeded and original is not None:
        ARCHIVE_PATH.write_bytes(original)
    assert succeeded, "Executing the compiled recovery program did not reproduce the exact archive"


def test_02_recovered_archive_exists_and_is_exact(expected_archive):
    assert ARCHIVE_PATH.is_file(), f"Recovered archive {ARCHIVE_PATH} does not exist."
    assert ARCHIVE_PATH.stat().st_size > 0, f"Recovered archive {ARCHIVE_PATH} is empty."
    assert ARCHIVE_PATH.read_bytes() == expected_archive, \
        "recovered.tar.gz is not the exact concatenation of payloads from raw_sensor.bin"
    with tarfile.open(ARCHIVE_PATH, "r:gz") as archive:
        assert archive.getmembers(), "Recovered archive is not a valid nonempty tar.gz"


def test_03_dataset_directory_exists_and_all_files_cleaned(expected_files):
    assert DATASET_DIR.is_dir(), f"Dataset directory {DATASET_DIR} does not exist."
    files = os.listdir(DATASET_DIR)
    assert len(files) > 0, "Dataset directory is empty."
    assert "log1.txt" in files, "log1.txt not found in extracted dataset."

    actual_paths = {
        str(p.relative_to(DATASET_DIR))
        for p in DATASET_DIR.rglob("*") if p.is_file()
    }
    assert actual_paths == set(expected_files), \
        f"Extracted file set is incorrect: expected {set(expected_files)}, got {actual_paths}"

    for relative, expected in expected_files.items():
        content = (DATASET_DIR / relative).read_bytes()
        assert content == expected, f"{relative} does not contain the exact cleaned recovered data"
        assert b"[ERR_CALIBRATION_LOSS]" not in content
        assert b"SENSOR_NODE_00" not in content

    content = (DATASET_DIR / "log1.txt").read_text(encoding="utf-8", errors="ignore")
    assert "[ERR_CALIBRATION_LOSS]" not in content, \
        "Found unreplaced '[ERR_CALIBRATION_LOSS]' in disk dataset."
    assert "SENSOR_NODE_00" not in content, \
        "Found unreplaced 'SENSOR_NODE_00' in disk dataset."


def request(relative, token=None):
    headers = {} if token is None else {"Authorization": f"Bearer {token}"}
    try:
        return requests.get(f"{BASE_URL}/data/{relative}", headers=headers, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to server: {exc}")


def test_04_server_unauthorized_no_header():
    response = request("log1.txt")
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized without header, got {response.status_code}"


def test_05_server_unauthorized_wrong_header():
    response = request("log1.txt", "wrong_token")
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized with wrong header, got {response.status_code}"


def test_06_server_authorized_returns_every_exact_file(expected_files):
    for relative, expected in expected_files.items():
        response = request(relative, AUTH_TOKEN)
        assert response.status_code == 200, \
            f"Expected 200 OK for {relative}, got {response.status_code}"
        assert response.content == expected, f"Server returned incorrect contents for {relative}"
        assert b"[ERR_CALIBRATION_LOSS]" not in response.content
        assert b"SENSOR_NODE_00" not in response.content

    content = request("log1.txt", AUTH_TOKEN).text
    assert "NaN" in content or "NODE_0" in content, \
        "Response body does not contain the expected cleaned replacements."


def test_07_server_is_a_native_compiled_process():
    listener_inodes = set()
    with open("/proc/net/tcp", "r", encoding="ascii") as table:
        next(table)
        for line in table:
            fields = line.split()
            if fields[1] == "0100007F:1F40" and fields[3] == "0A":
                listener_inodes.add(fields[9])
    assert listener_inodes, "No process is listening on 127.0.0.1:8000"

    pids = set()
    for procdir in Path("/proc").iterdir():
        if not procdir.name.isdigit():
            continue
        fd_dir = procdir / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in listener_inodes:
                    pids.add(procdir.name)
        except (OSError, PermissionError):
            continue
    assert pids, "Could not identify the server process"

    native = False
    for pid in pids:
        try:
            exe = Path(os.readlink(f"/proc/{pid}/exe"))
            with exe.open("rb") as f:
                native = native or f.read(4) == b"\x7fELF"
        except OSError:
            pass
    assert native, "The HTTP server is not running as a native compiled executable"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
