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

REAL_VALIDATOR=/app/validator.verifier-real
CALL_LOG=/tmp/validator_calls.log
rm -f "$CALL_LOG" /tmp/verified-archive.*

cleanup() {
    if [ -e "$REAL_VALIDATOR" ]; then
        rm -f /app/validator
        mv "$REAL_VALIDATOR" /app/validator
    fi
}
trap cleanup EXIT

mv /app/validator "$REAL_VALIDATOR"
cat << 'WRAPPER_EOF' > /app/validator
#!/bin/bash
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    exit 97
fi
copy=$(mktemp /tmp/verified-archive.XXXXXX) || exit 98
cp -- "$1" "$copy" || exit 99
printf '%s\t%s\n' "$1" "$copy" >> /tmp/validator_calls.log
exec /app/validator.verifier-real "$@"
WRAPPER_EOF
chmod 755 /app/validator
touch "$CALL_LOG"
chmod 666 "$CALL_LOG"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import random
import secrets
import string
import subprocess
import struct

import pytest
import requests

URL = "http://127.0.0.1:8888/pack"
EXPECTED_VALIDATED_ARCHIVES = []


def serialize_expected(payload):
    out = bytearray(b"ARCH")
    out += struct.pack("<I", payload["project_id"])
    out += struct.pack("<H", len(payload["files"]))
    for entry in payload["files"]:
        name = entry["name"].encode("ascii")
        content = entry["content"].encode("ascii")
        out += struct.pack("<H", len(name))
        out += name
        out += struct.pack("<I", len(content))
        out += content
    return bytes(out)


def test_pack_success():
    payload = {
        "project_id": 999,
        "files": [
            {"name": "test.txt", "content": "12345"},
            {"name": "dir/file", "content": "abcdef"}
        ]
    }
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {URL}: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Body: {response.text}"

    expected_magic = b"ARCH"
    expected_proj_id = struct.pack("<I", 999)
    expected_num_files = struct.pack("<H", 2)

    file1_name_len = struct.pack("<H", 8)
    file1_name = b"test.txt"
    file1_content_len = struct.pack("<I", 5)
    file1_content = b"12345"

    file2_name_len = struct.pack("<H", 8)
    file2_name = b"dir/file"
    file2_content_len = struct.pack("<I", 6)
    file2_content = b"abcdef"

    expected_body = (
        expected_magic + expected_proj_id + expected_num_files +
        file1_name_len + file1_name + file1_content_len + file1_content +
        file2_name_len + file2_name + file2_content_len + file2_content
    )

    assert response.content == expected_body, f"Binary response mismatch. Expected {expected_body.hex()}, got {response.content.hex()}"
    assert response.headers.get("Content-Type") == "application/octet-stream", "Expected Content-Type: application/octet-stream"
    EXPECTED_VALIDATED_ARCHIVES.append(expected_body)


def test_pack_dynamic():
    payload = {
        "project_id": 42,
        "files": [
            {"name": "a", "content": "b"}
        ]
    }
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {URL}: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Body: {response.text}"

    expected_body = b"ARCH" + struct.pack("<I", 42) + struct.pack("<H", 1) + \
                    struct.pack("<H", 1) + b"a" + struct.pack("<I", 1) + b"b"

    assert response.content == expected_body, f"Binary response mismatch for dynamic test."
    EXPECTED_VALIDATED_ARCHIVES.append(expected_body)


def test_randomized_archives():
    alphabet = string.ascii_letters + string.digits
    rng = random.SystemRandom()

    for case in range(6):
        files = []
        for index in range(1 + case % 5):
            stem = ''.join(rng.choice(alphabet) for _ in range(rng.randint(3, 18)))
            name = f"d{case}/{stem}.{index}"
            content = ''.join(rng.choice(alphabet + " _-.,:;/") for _ in range(rng.randint(1, 180)))
            files.append({"name": name, "content": content})

        payload = {"project_id": secrets.randbits(32), "files": files}
        expected = serialize_expected(payload)
        try:
            response = requests.post(URL, json=payload, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed randomized request {case}: {e}")

        assert response.status_code == 200, f"Randomized request {case} returned {response.status_code}"
        assert response.headers.get("Content-Type") == "application/octet-stream"
        assert response.content == expected, (
            f"Randomized archive {case} mismatch: expected {expected.hex()}, got {response.content.hex()}"
        )
        EXPECTED_VALIDATED_ARCHIVES.append(expected)


def test_malformed_json():
    try:
        response = requests.post(URL, data="not json", headers={"Content-Type": "application/json"}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Server crashed or failed to connect on malformed JSON: {e}")

    assert response.status_code != 200, f"Expected non-200 status code for malformed JSON, got {response.status_code}"


def test_validator_received_generated_temporary_archives():
    lines = pathlib.Path("/tmp/validator_calls.log").read_text().splitlines()
    assert len(lines) >= len(EXPECTED_VALIDATED_ARCHIVES), "The server did not invoke /app/validator for each successful archive"

    validated = []
    for line in lines:
        original, copied = line.split("\t", 1)
        assert original, "Validator was invoked without an archive path"
        copy_path = pathlib.Path(copied)
        assert copy_path.is_file(), "The archive passed to the validator was not a real file"
        validated.append(copy_path.read_bytes())

    for expected in EXPECTED_VALIDATED_ARCHIVES:
        assert expected in validated, "A returned archive was not written to a file and passed to /app/validator"


def listening_server_pid():
    inode = None
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if int(local.rsplit(":", 1)[1], 16) == 8888 and state == "0A":
                inode = fields[9]
                break
        if inode:
            break
    assert inode, "No process is listening on port 8888"

    target = f"socket:[{inode}]"
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    if os.readlink(fd) == target:
                        return int(proc.name)
                except OSError:
                    pass
        except (OSError, PermissionError):
            pass
    pytest.fail("Could not identify the process listening on port 8888")


def test_z_c_library_and_makefile():
    pid = listening_server_pid()
    maps = pathlib.Path(f"/proc/{pid}/maps").read_text().splitlines()
    mapped = []
    for line in maps:
        parts = line.split(None, 5)
        if len(parts) == 6:
            candidate = parts[5].replace(" (deleted)", "")
            if pathlib.Path(candidate).name == "libpack.so":
                mapped.append(pathlib.Path(candidate))

    assert mapped, "The listening server process has not loaded libpack.so"
    library = next((p for p in mapped if p.is_file()), None)
    assert library is not None, "The loaded libpack.so no longer exists on disk"

    file_info = subprocess.run(["file", str(library)], capture_output=True, text=True, timeout=5)
    assert file_info.returncode == 0 and "ELF" in file_info.stdout and "shared object" in file_info.stdout, \
        "libpack.so is not an ELF shared library"

    candidates = []
    for root in {library.parent, pathlib.Path("/home/user"), pathlib.Path("/app")}:
        try:
            candidates.extend(root.rglob("Makefile"))
        except OSError:
            pass
    makefile = next((p for p in candidates if "libpack.so" in p.read_text(errors="ignore")), None)
    assert makefile is not None, "No Makefile that builds libpack.so was found"

    c_sources = list(makefile.parent.glob("*.c"))
    assert c_sources, "No C serialization source was found beside the Makefile"
    source_text = "\n".join(p.read_text(errors="ignore") for p in c_sources)
    assert "ARCH" in source_text, "The C source does not contain the archive serialization magic"

    build = subprocess.run(["make", "-B"], cwd=makefile.parent, capture_output=True, text=True, timeout=20)
    assert build.returncode == 0, f"Makefile failed to rebuild libpack.so:\n{build.stdout}\n{build.stderr}"
    rebuilt = makefile.parent / "libpack.so"
    assert rebuilt.is_file(), "Makefile did not produce libpack.so"
    rebuilt_info = subprocess.run(["file", str(rebuilt)], capture_output=True, text=True, timeout=5)
    assert "ELF" in rebuilt_info.stdout and "shared object" in rebuilt_info.stdout, "Rebuilt libpack.so is not a shared library"
TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
