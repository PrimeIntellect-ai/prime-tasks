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
import collections
import json
import os
import re
import subprocess
import tarfile
import threading
import time
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8888"
LOG_DIR = Path("/app/logs")


def read_zone_id():
    result = subprocess.run(
        ["tesseract", "/app/system_tag.png", "stdout"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        check=True,
    )
    zone = result.stdout.strip()
    assert zone, "OCR produced an empty Zone ID"
    assert re.fullmatch(r"[A-Za-z0-9_-]+", zone), f"Unexpected OCR Zone ID: {zone!r}"
    return zone


ZONE_ID = read_zone_id()
EXPECTED_BASENAMES = [f"processed_{ZONE_ID}_{i:03d}.log" for i in range(1, 4)]
EXPECTED_PATHS = [LOG_DIR / name for name in EXPECTED_BASENAMES]


def test_renamed_files():
    for path in EXPECTED_PATHS:
        assert path.is_file(), f"Expected processed file {path} is missing"
        assert path.read_bytes() == b"data\n", f"Contents of {path} were not preserved"

    for i in range(1, 4):
        raw = LOG_DIR / f"raw_{ZONE_ID}_{i:03d}.log"
        assert not raw.exists(), f"Raw file {raw} should have been renamed"

    processed = sorted(
        p.name for p in LOG_DIR.iterdir()
        if p.is_file() and p.name.startswith(f"processed_{ZONE_ID}_") and p.name.endswith(".log")
    )
    assert processed == EXPECTED_BASENAMES, (
        f"Processed files for OCR-derived zone are incomplete or contain extras: {processed}"
    )

    remaining_matching_raw = sorted(LOG_DIR.glob(f"raw_{ZONE_ID}_*.log"))
    assert not remaining_matching_raw, f"Matching raw files remain: {remaining_matching_raw}"


def test_untouched_files():
    untouched = LOG_DIR / "raw_OTHER-11A_001.log"
    assert untouched.is_file(), f"File {untouched} should remain untouched"
    assert untouched.read_bytes() == b"data\n", "Unrelated zone log contents changed"


def test_archive_exists_and_valid():
    archive_path = Path(f"/app/archive_{ZONE_ID}.tar.gz")
    assert archive_path.is_file(), f"Archive {archive_path} is missing"

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        archived_files = []

        for member in members:
            normalized = member.name
            while normalized.startswith("./"):
                normalized = normalized[2:]

            assert not member.name.startswith("/"), f"Archive contains absolute path {member.name!r}"
            assert ".." not in Path(normalized).parts, f"Archive contains traversal path {member.name!r}"

            if member.isdir():
                assert normalized.rstrip("/") in ("", ".", "logs"), (
                    f"Archive contains unrelated directory {member.name!r}"
                )
                continue

            assert member.isfile(), f"Archive contains a non-regular entry {member.name!r}"
            parts = Path(normalized).parts
            assert len(parts) == 1 or (len(parts) == 2 and parts[0] == "logs"), (
                f"File {member.name!r} is not at archive root or under logs/"
            )

            basename = parts[-1]
            archived_files.append(basename)
            extracted = tar.extractfile(member)
            assert extracted is not None
            assert extracted.read() == (LOG_DIR / basename).read_bytes(), (
                f"Archived contents for {basename} differ from the renamed log"
            )

    assert collections.Counter(archived_files) == collections.Counter(EXPECTED_BASENAMES), (
        f"Archive must contain exactly the renamed logs; found {archived_files}"
    )


def test_server_info_endpoint():
    try:
        response = requests.get(f"{BASE_URL}/info", timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {BASE_URL}/info: {exc}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    assert data.get("zone") == ZONE_ID, f"Expected zone {ZONE_ID}, got {data.get('zone')}"
    assert data.get("files_archived") == len(EXPECTED_BASENAMES), (
        f"Expected files_archived {len(EXPECTED_BASENAMES)}, got {data.get('files_archived')}"
    )


def listening_server_pid():
    socket_inodes = set()
    with open("/proc/net/tcp", "r") as handle:
        next(handle)
        for line in handle:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            host_hex, port_hex = local_address.split(":")
            if host_hex == "0100007F" and int(port_hex, 16) == 8888 and state == "0A":
                socket_inodes.add(inode)

    assert socket_inodes, "No process is listening on 127.0.0.1:8888"
    for proc_entry in Path("/proc").iterdir():
        if not proc_entry.name.isdigit():
            continue
        fd_dir = proc_entry / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    return int(proc_entry.name)
        except (FileNotFoundError, PermissionError):
            continue
    pytest.fail("Could not identify the process owning 127.0.0.1:8888")


def executed_server_source():
    pid = listening_server_pid()
    cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    args = [part.decode(errors="replace") for part in cmdline if part]
    assert args and "python" in os.path.basename(args[0]).lower(), (
        f"Port 8888 is not owned by a Python server: {args}"
    )

    cwd = Path(os.readlink(f"/proc/{pid}/cwd"))
    candidates = []
    for arg in args[1:]:
        if arg.endswith(".py"):
            path = Path(arg)
            if not path.is_absolute():
                path = cwd / path
            if path.is_file():
                candidates.append(path.resolve())

    assert candidates, f"Could not locate the running Python server's source file from {args}"
    return "\n".join(path.read_text(errors="replace") for path in candidates)


def test_server_uses_required_locking_and_atomic_replace():
    source = executed_server_source()
    assert re.search(r"(^|\n)\s*(import\s+fcntl\b|from\s+fcntl\s+import\b)", source), (
        "Running server source does not import fcntl"
    )
    assert re.search(r"\b(?:fcntl\s*\.\s*)?flock\s*\(", source), (
        "Running server source does not call flock"
    )
    assert re.search(r"\b(?:fcntl\s*\.\s*)?LOCK_EX\b", source), (
        "Running server source does not request an exclusive file lock"
    )
    assert re.search(r"\b(?:os\s*\.\s*)?(?:replace|rename)\s*\(", source) or re.search(
        r"\.replace\s*\(", source
    ), "Running server source does not atomically rename/replace the registry"
    assert re.search(r"tempfile|mkstemp|NamedTemporaryFile|\.tmp\b|temp(?:_|\s*)path", source, re.I), (
        "Running server source shows no temporary-file write before replacement"
    )


def test_server_register_concurrency_preserves_contents_atomically():
    registry_path = Path("/app/registry.json")
    seed = [f"preserved_{i}_" + ("x" * 8192) for i in range(64)]
    temporary = Path("/app/.verifier_registry_seed.tmp")
    temporary.write_text(json.dumps(seed))
    os.replace(temporary, registry_path)
    initial_inode = registry_path.stat().st_ino

    errors = []
    invalid_snapshots = []
    stop_observer = threading.Event()

    def observe_registry():
        while not stop_observer.is_set():
            try:
                value = json.loads(registry_path.read_text())
                if not isinstance(value, list):
                    invalid_snapshots.append("registry was not an array")
                    return
            except (OSError, json.JSONDecodeError) as exc:
                invalid_snapshots.append(str(exc))
                return
            time.sleep(0.001)

    def post_register(i):
        try:
            payload = {"filename": f"test_{i}.log"}
            response = requests.post(f"{BASE_URL}/register", json=payload, timeout=15)
            if response.status_code not in (200, 201, 204):
                errors.append(f"Request {i} failed with status {response.status_code}")
        except Exception as exc:
            errors.append(f"Request {i} exception: {exc}")

    observer = threading.Thread(target=observe_registry)
    observer.start()
    threads = [threading.Thread(target=post_register, args=(i,)) for i in range(10)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    stop_observer.set()
    observer.join()

    assert not errors, f"Errors occurred during concurrent POST requests: {errors}"
    assert not invalid_snapshots, f"Registry was observably non-atomic: {invalid_snapshots}"
    assert registry_path.is_file(), f"Registry file {registry_path} is missing"
    assert registry_path.stat().st_ino != initial_inode, (
        "Registry inode did not change; updates were not installed by atomic replacement"
    )

    try:
        registry = json.loads(registry_path.read_text())
    except json.JSONDecodeError:
        pytest.fail("registry.json is not valid JSON")

    assert isinstance(registry, list), "registry.json should contain a JSON array"
    assert registry[:len(seed)] == seed, "Existing registry contents were not preserved"

    expected = [f"test_{i}.log" for i in range(10)]
    appended = registry[len(seed):]
    assert collections.Counter(appended) == collections.Counter(expected), (
        f"Concurrent registrations were lost, duplicated, or polluted: {appended}"
    )
    assert len(registry) == len(seed) + len(expected), (
        "Registry contains unrelated or duplicate entries"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
